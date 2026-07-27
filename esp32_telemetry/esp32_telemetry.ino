#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h> // Include secure client library
#include <ArduinoJson.h>
#include <Wire.h>
#include <RTClib.h>
#include <Preferences.h>
#include <WebServer.h>
#include <DNSServer.h>
#include <ArduinoOTA.h>
#include <ESPmDNS.h>

// --- Network & Supabase Credentials ---
#include "secrets.h" // secrets.h no longer needs SSID and Password!

const char* deviceId = "ESP32_SOLAR_001";

// --- Hardware Pins ---
const int batteryPin = 34;   
const int chargingPin = 33;   // Moved from GPIO 35 (no pull-up support) to GPIO 33
const int motorRelayPin = 4; // Assuming GPIO 4 for your water pump relay
const int soilPowerPin = 32; // Powers the moisture sensor only when reading
const int soilSensorPin = 35; // Analog read for moisture
const int solarPin = 36; // VP pin (ADC1_CH0) for solar voltage via 47k+47k divider

// --- Continuous Loop Timers ---
unsigned long lastCommandCheck = 0;
unsigned long lastTelemetryUpload = 0;
const unsigned long COMMAND_INTERVAL  = 3000;   // Poll commands every 3 seconds
const unsigned long TELEMETRY_INTERVAL = 5000;  // Upload telemetry every 5 seconds

// --- Non-blocking Motor State ---
bool motorRunning = false;
unsigned long motorStartTime = 0;
unsigned long motorDuration = 0; // in milliseconds
int lastDailyWateringDay = -1;   // Tracks which day daily schedule last fired (-1 = never)
bool hasWifiResetColumn = true;
bool soilSensorEnabled = true; // Set by Supabase profiles table

// --- RTC Setup ---
RTC_DS3231 rtc;

// --- SoftAP Configuration Globals ---
WebServer server(80);
bool softAPConfigReceived = false;
bool softAPStarted = false;
bool softAPActive = false;
unsigned long softAPStartTime = 0;
DNSServer dnsServer;

// --- Cached WiFi Scan Results (scanned BEFORE connecting so radio is free) ---
String cachedNetworksJson = "{\"networks\":[]}";
bool scanInProgress = false;

// --- WiFi State Machine ---
// We track connecting state ourselves because ESP32 IDF status lags behind reality.
bool wifiConnecting = false;          // True when we've called WiFi.begin() and are waiting
unsigned long wifiConnectStartTime = 0; // When did the current attempt begin?

// --- Persistent Credentials Storage ---
Preferences preferences;

void updateDatabaseWifiReset(bool reset);

void loadWiFiCredentials(String &ssid, String &password) {
  preferences.begin("solak-wifi", true);
  ssid = preferences.getString("ssid", "");
  password = preferences.getString("password", "");
  preferences.end();
}

void saveWiFiCredentials(String ssid, String password) {
  preferences.begin("solak-wifi", false);
  preferences.putString("ssid", ssid);
  preferences.putString("password", password);
  preferences.end();
}

// Scan for networks and cache the result as JSON.
// MUST be called while WiFi is NOT actively connecting (i.e. before WiFi.begin())
void performWifiScan() {
  if (scanInProgress) return;
  scanInProgress = true;
  Serial.println("Scanning for nearby WiFi networks...");

  // Use synchronous scan - safe ONLY when called before WiFi.begin()
  int n = WiFi.scanNetworks();
  Serial.printf("Scan complete. Found %d networks.\n", n);

  // Build de-duplicated JSON
  String uniqueSSIDs[20];
  int uniqueCount = 0;
  String jsonArr = "[";
  bool first = true;

  for (int i = 0; i < n && uniqueCount < 20; i++) {
    String ssid = WiFi.SSID(i);
    if (ssid.length() == 0) continue;
    bool dup = false;
    for (int j = 0; j < uniqueCount; j++) {
      if (uniqueSSIDs[j] == ssid) { dup = true; break; }
    }
    if (!dup) {
      uniqueSSIDs[uniqueCount++] = ssid;
      if (!first) jsonArr += ",";
      // Escape any quotes in SSID name
      ssid.replace("\\", "\\\\");
      ssid.replace("\"", "\\\"");
      jsonArr += "\"" + ssid + "\"";
      first = false;
    }
  }
  jsonArr += "]";
  cachedNetworksJson = "{\"networks\":" + jsonArr + "}";
  WiFi.scanDelete(); // Free scan memory
  scanInProgress = false;
  Serial.println("Cached scan: " + cachedNetworksJson);
}

void startSoftAPProvisioning() {
  if (!softAPActive) {
    Serial.println("Starting SoftAP Provisioning...");
    WiFi.mode(WIFI_AP_STA);
    WiFi.softAP("Solak_Setup");
    dnsServer.start(53, "*", IPAddress(192, 168, 4, 1));
    softAPStartTime = millis();
    softAPActive = true;
  }
  if (softAPStarted) return;
  
  // 1. Root page handler serving a premium WiFi Captive Portal HTML form
  server.on("/", HTTP_GET, []() {
    String html = "<!DOCTYPE html><html><head><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">";
    html += "<title>Solak WiFi Setup</title><style>";
    html += "body { background-color: #0a0f0a; color: white; font-family: sans-serif; text-align: center; padding: 20px; }";
    html += "h2 { color: #34d399; margin-top: 20px; }";
    html += "select, input, button { width: 100%; max-width: 300px; padding: 14px; margin: 10px 0; border-radius: 12px; border: 1px solid #222; box-sizing: border-box; font-size: 14px; }";
    html += "select, input { background: #16221a; color: white; border: 1px solid #2a3d30; }";
    html += "button { background: #34d399; color: #0a0f0a; font-weight: bold; border: none; cursor: pointer; transition: opacity 0.2s; }";
    html += ".btn-refresh { background: #16221a; color: #34d399; border: 1px solid #34d399; margin-top: 5px; margin-bottom: 20px; }";
    html += "button:hover { opacity: 0.9; }";
    html += "form { margin-top: 10px; }";
    html += ".note { color: #888; font-size: 11px; margin-top: 20px; line-height: 1.4; }";
    html += ".loader { border: 3px solid #222; border-top: 3px solid #34d399; border-radius: 50%; width: 24px; height: 24px; animation: spin 1s linear infinite; display: inline-block; margin-bottom: 10px; }";
    html += "@keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }";
    html += "</style>";
    html += "<script>";
    html += "function loadFromCache() {";
    html += "  fetch('/scan').then(r => r.json()).then(data => {";
    html += "    populateList(data);";
    html += "  }).catch(() => {";
    html += "    document.getElementById('status').innerHTML = 'Could not reach device. Enter network name manually.';";
    html += "  });";
    html += "}";
    html += "function rescan() {";
    html += "  document.getElementById('status').innerHTML = '<div class=\"loader\"></div><br>Rescanning...';";
    html += "  document.getElementById('ssid-select').style.display = 'none';";
    html += "  fetch('/rescan').then(r => r.json()).then(data => {";
    html += "    populateList(data);";
    html += "  }).catch(() => {";
    html += "    document.getElementById('status').innerHTML = 'Rescan failed. Enter network name manually.';";
    html += "  });";
    html += "}";
    html += "function populateList(data) {";
    html += "  let select = document.getElementById('ssid-select');";
    html += "  select.innerHTML = '<option value=\"\">-- Select Network --</option>';";
    html += "  if(data.networks && data.networks.length > 0) {";
    html += "    data.networks.forEach(ssid => {";
    html += "      select.innerHTML += '<option value=\"' + ssid + '\">' + ssid + '</option>';";
    html += "    });";
    html += "    select.style.display = 'inline-block';";
    html += "    document.getElementById('status').innerHTML = data.networks.length + ' networks found.';";
    html += "  } else {";
    html += "    document.getElementById('status').innerHTML = 'No networks in range. Enter your Wi-Fi name manually below.';";
    html += "  }";
    html += "}";
    html += "function onSelectChange() {";
    html += "  let select = document.getElementById('ssid-select');";
    html += "  if(select.value !== '') { document.getElementById('ssid-input').value = select.value; }";
    html += "}";
    html += "window.onload = loadFromCache;";
    html += "</script>";
    html += "</head><body>";
    html += "<h2>Solak Device Setup</h2>";
    html += "<p style=\"color: #ccc; font-size: 14px;\">Connect your Solak hardware node to Wi-Fi.</p>";
    html += "<button type=\"button\" class=\"btn-refresh\" onclick=\"rescan()\">↻ Scan Networks</button>";
    html += "<div id=\"status\"></div>";
    html += "<form method=\"POST\" action=\"/connect_html\">";
    html += "<select id=\"ssid-select\" style=\"display:none;\" onchange=\"onSelectChange()\"></select><br>";
    html += "<input type=\"text\" id=\"ssid-input\" name=\"ssid\" placeholder=\"Wi-Fi Network Name\" required><br>";
    html += "<input type=\"password\" name=\"pass\" placeholder=\"Wi-Fi Password\"><br>";
    html += "<button type=\"submit\">Connect Device</button>";
    html += "</form>";
    html += "<p class=\"note\">Once sent, the device will connect to your router and the Solak_Setup hotspot will turn off.</p>";
    html += "</body></html>";
    
    server.send(200, "text/html", html);
  });

  // 2. HTML connect handler
  server.on("/connect_html", HTTP_POST, []() {
    String ssid = server.arg("ssid");
    String pass = server.arg("pass");
    if (ssid.length() > 0) {
      saveWiFiCredentials(ssid, pass);
      softAPConfigReceived = true;
      String html = "<html><head><meta name='viewport' content='width=device-width, initial-scale=1'><style>body{background-color:#0a0f0a;color:white;font-family:sans-serif;text-align:center;padding:50px;}h2{color:#34d399;}</style></head><body><h2>Credentials Saved!</h2><p>Connecting to WiFi. You can close this window now.</p></body></html>";
      server.send(200, "text/html", html);
    } else {
      server.send(400, "text/plain", "SSID is required");
    }
  });

  // 3. JSON Scan API endpoint — serves from CACHE (safe to call at any time)
  // The browser JS calls this endpoint; we serve pre-scanned results instantly.
  server.on("/scan", HTTP_GET, []() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Cache-Control", "no-cache");
    server.send(200, "application/json", cachedNetworksJson);
  });

  // 3b. Trigger a fresh async scan (only safe when WiFi is not mid-connection)
  server.on("/rescan", HTTP_GET, []() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    if (WiFi.status() != WL_CONNECTED && !scanInProgress) {
      performWifiScan(); // Safe: not connected, radio is free
      server.send(200, "application/json", cachedNetworksJson);
    } else {
      // Return cached while connected/scanning
      server.send(200, "application/json", cachedNetworksJson);
    }
  });
  
  // 4. JSON Connect API endpoint for Flutter App compatibility
  server.on("/connect", HTTP_POST, []() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    if (server.hasArg("plain") == false) {
      server.send(400, "text/plain", "Body not received");
      return;
    }
    
    String body = server.arg("plain");
    #if ARDUINOJSON_VERSION_MAJOR >= 7
    JsonDocument doc;
    #else
    DynamicJsonDocument doc(512);
    #endif
    
    DeserializationError error = deserializeJson(doc, body);
    if (!error) {
      String ssid = doc["ssid"] | "";
      String pass = doc["pass"] | "";
      if (ssid.length() > 0) {
        saveWiFiCredentials(ssid, pass);
        softAPConfigReceived = true;
        server.send(200, "application/json", "{\"status\":\"connecting\"}");
        return;
      }
    }
    server.send(400, "application/json", "{\"error\":\"Invalid request\"}");
  });
  
  // 5. JSON Status API endpoint for Flutter App compatibility
  server.on("/status", HTTP_GET, []() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    if (WiFi.status() == WL_CONNECTED) {
      server.send(200, "application/json", "{\"status\":\"connected\"}");
    } else {
      server.send(200, "application/json", "{\"status\":\"waiting\"}");
    }
  });

  // 6. Captive Portal Redirect Handler
  server.onNotFound([]() {
    server.sendHeader("Location", "http://192.168.4.1/", true);
    server.send(302, "text/plain", "");
  });
  
  server.begin();
  softAPStarted = true;
  Serial.println("SoftAP Provisioning WebServer started.");
}

// Safe WiFi start: always do a hard reset of the station driver before begin().
// This is the ONLY reliable way to avoid "sta is connecting, cannot set config" on ESP32.
void safeWifiBegin(const char* ssid, const char* pass) {
  Serial.printf("[WiFi] safeWifiBegin() -> SSID: %s\n", ssid);

  // 1. Bring the station fully down
  WiFi.disconnect(true); // true = also clear IDF's internal AP config
  delay(300);            // Wait for IDF state machine to reach IDLE

  // 2. In AP+STA mode the AP stays alive; we only reset the STA interface
  //    Re-setting WIFI_AP_STA re-initialises the STA side cleanly.
  WiFi.mode(WIFI_AP_STA);
  delay(100);

  // 3. Now begin — IDF is guaranteed to be in IDLE state
  WiFi.begin(ssid, pass);
  wifiConnecting = true;
  wifiConnectStartTime = millis();
  Serial.println("[WiFi] Connection attempt started.");
}

void connectWiFi() {
  // Always start SoftAP so the setup portal is always reachable
  startSoftAPProvisioning();

  String ssid = "";
  String password = "";
  loadWiFiCredentials(ssid, password);

  if (ssid.length() > 0) {
    safeWifiBegin(ssid.c_str(), password.c_str());
  } else {
    Serial.println("[WiFi] No credentials saved. Configure via Solak_Setup portal.");
  }
}

void setup() {
  Serial.begin(115200);
  delay(500);
  
  Serial.println("\n-------------------------------------------");
  Serial.println("ESP32 Solak - Continuous Mode");
  Serial.println("-------------------------------------------");

  pinMode(motorRelayPin, OUTPUT); 
  digitalWrite(motorRelayPin, HIGH); // Default OFF state
  
  pinMode(soilPowerPin, OUTPUT);
  digitalWrite(soilPowerPin, LOW); // Keep soil sensor OFF to save power/prevent corrosion

  // 1. SCAN FIRST while the radio is completely idle (nothing else running yet)
  //    Results are cached in memory and served by /scan at any time.
  WiFi.mode(WIFI_STA);
  performWifiScan();

  // 2. Start SoftAP + attempt WiFi connection (non-blocking from here)
  connectWiFi();

  // 3. Initialize RTC
  Wire.begin();
  if (!rtc.begin()) {
    Serial.println("Couldn't find RTC! Check connections.");
  } else {
    Serial.println("RTC initialized successfully.");
    if (rtc.lostPower()) {
      Serial.println("RTC lost power, setting time to compile time.");
      rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
    }
  }
  
  // 4. Initialize Over-The-Air (OTA) Updates
  ArduinoOTA.setHostname("Solak-ESP32");
  ArduinoOTA.setPassword("admin123");
  ArduinoOTA.begin();
}

void loop() {
  ArduinoOTA.handle(); // Listen for wireless firmware updates

  // Handle SoftAP provisioning server if active
  if (softAPActive) {
    dnsServer.processNextRequest();
    server.handleClient();
    
    // Check for 10-minute timeout to shut down the AP (600000 ms)
    if (millis() - softAPStartTime >= 600000 && WiFi.status() == WL_CONNECTED) {
      Serial.println("SoftAP timeout reached. Shutting down Solak_Setup hotspot...");
      WiFi.softAPdisconnect(true);
      WiFi.mode(WIFI_STA); // Switch to station only to save power
      softAPActive = false;
    }
  }

  // If new credentials received via SoftAP, connect immediately
  if (softAPConfigReceived) {
    softAPConfigReceived = false;
    String ssid = "", pass = "";
    loadWiFiCredentials(ssid, pass);
    Serial.print("[WiFi] New credentials received for: ");
    Serial.println(ssid);
    safeWifiBegin(ssid.c_str(), pass.c_str());
  }

  // --- WiFi State Machine ---
  if (wifiConnecting) {
    wl_status_t s = WiFi.status();

    if (s == WL_CONNECTED) {
      // SUCCESS
      wifiConnecting = false;
      Serial.println("[WiFi] Connected successfully!");

    } else if (s == WL_CONNECT_FAILED || s == WL_NO_SSID_AVAIL) {
      // DEFINITIVE FAILURE — wrong password or network not found
      wifiConnecting = false;
      Serial.printf("[WiFi] Connection failed (status=%d). Wrong password or SSID not found.\n", s);
      WiFi.disconnect(true);

    } else if (millis() - wifiConnectStartTime > 20000) {
      // TIMEOUT — driver is stuck. Force a full hard reset.
      wifiConnecting = false;
      Serial.println("[WiFi] Connection timed out. Performing hard reset of WiFi driver...");
      WiFi.mode(WIFI_OFF);   // Completely shut down radio
      delay(500);
      WiFi.mode(WIFI_AP_STA); // Restart radio in AP+STA mode
      delay(200);
      WiFi.softAP("Solak_Setup"); // Restart the AP
      delay(200);
      Serial.println("[WiFi] WiFi driver reset. Will retry on next cycle.");
    }
    // Still connecting — do nothing and let it run
  } else if (WiFi.status() != WL_CONNECTED) {
    // Not connecting and not connected — schedule a retry
    static unsigned long lastReconnectAttempt = 0;
    if (millis() - lastReconnectAttempt > 30000) { // Retry every 30s
      lastReconnectAttempt = millis();
      String ssid = "", pass = "";
      loadWiFiCredentials(ssid, pass);
      if (ssid.length() > 0) {
        Serial.println("[WiFi] Not connected. Scheduling reconnect attempt...");
        safeWifiBegin(ssid.c_str(), pass.c_str());
      }
    }
  }

  // If not connected yet (connecting or waiting), keep portal alive and skip telemetry
  if (WiFi.status() != WL_CONNECTED) {
    if (softAPActive) {
      dnsServer.processNextRequest();
      server.handleClient();
    }
    return;
  }


  unsigned long now = millis();

  // --- Non-blocking motor shutoff check ---
  if (motorRunning && (now - motorStartTime >= motorDuration)) {
    pinMode(motorRelayPin, OUTPUT);
    digitalWrite(motorRelayPin, HIGH); // Release relay (turns OFF)
    motorRunning = false;
    Serial.println("Watering cycle complete.");
    updateDatabaseMotorActive(false);
  }

  // Check for watering commands every 3 seconds
  if (now - lastCommandCheck >= COMMAND_INTERVAL) {
    lastCommandCheck = now;
    processWateringLogic();
  }

  // Upload telemetry every 5 seconds
  if (now - lastTelemetryUpload >= TELEMETRY_INTERVAL) {
    lastTelemetryUpload = now;
    sendTelemetryData();
  }
}

// ==========================================
// PROCESS MANUAL COMMANDS AND SCHEDULES
// ==========================================
void processWateringLogic() {
  WiFiClientSecure client;
  client.setInsecure(); // Bypass SSL certificate validation to prevent connection code -1
  HTTPClient http;
  
  String url;
  if (hasWifiResetColumn) {
    url = String(supabaseUrl) + "/rest/v1/profiles?select=motor_active,daily_watering_enabled,daily_watering_time,watering_duration,sleep_interval,wifi_reset,soil_sensor_enabled&id=eq." + String(userId);
  } else {
    url = String(supabaseUrl) + "/rest/v1/profiles?select=motor_active,daily_watering_enabled,daily_watering_time,watering_duration,sleep_interval,soil_sensor_enabled&id=eq." + String(userId);
  }
  http.begin(client, url);
  http.setReuse(false); // Fix memory leak causing -1
  
  http.addHeader("apikey", supabaseKey);
  http.addHeader("Authorization", "Bearer " + String(supabaseKey));

  int httpResponseCode = http.GET();
  Serial.print("GET (Command Check) Response Code: ");
  Serial.println(httpResponseCode);

  // Fallback if wifi_reset column does not exist in database yet (prevents HTTP 400 error)
  if (httpResponseCode == 400 && hasWifiResetColumn) {
    hasWifiResetColumn = false;
    Serial.println("Column wifi_reset does not exist in database. Switched to compact query.");
    http.end();
    url = String(supabaseUrl) + "/rest/v1/profiles?select=motor_active,daily_watering_enabled,daily_watering_time,watering_duration,sleep_interval,soil_sensor_enabled&id=eq." + String(userId);
    http.begin(client, url);
    http.addHeader("apikey", supabaseKey);
    http.addHeader("Authorization", "Bearer " + String(supabaseKey));
    httpResponseCode = http.GET();
    Serial.print("Fallback GET Response Code: ");
    Serial.println(httpResponseCode);
  }

  if (httpResponseCode == 200) {
    String payload = http.getString();
    Serial.print("Payload received: ");
    Serial.println(payload);
    
    #if ARDUINOJSON_VERSION_MAJOR >= 7
    JsonDocument doc;
    #else
    DynamicJsonDocument doc(512);
    #endif
    
    DeserializationError error = deserializeJson(doc, payload);
    
    if (!error && doc.size() > 0) {
      bool motorActive = doc[0]["motor_active"] | false;
      bool dailyEnabled = doc[0]["daily_watering_enabled"] | false;
      String dailyTime = doc[0]["daily_watering_time"] | "08:00:00";
      int duration = doc[0]["watering_duration"] | 15;
      bool wifiReset = doc[0]["wifi_reset"] | false;
      soilSensorEnabled = doc[0]["soil_sensor_enabled"] | true; // Update global state

      // Handle remote WiFi reset command
      if (wifiReset) {
        Serial.println("WiFi reset command received! Clearing credentials...");
        preferences.begin("solak-wifi", false);
        preferences.clear();
        preferences.end();
        
        // Reset the flag in database
        updateDatabaseWifiReset(false);
        
        // Restart WiFi stack and open hotspot
        WiFi.disconnect(true);
        delay(300);
        WiFi.mode(WIFI_OFF);
        delay(500);
        WiFi.mode(WIFI_STA);
        delay(300);
        startSoftAPProvisioning();
        return; // Terminate loop iteration since we are going back to onboarding AP
      }

      bool triggerWatering = false;

      // Check 1: Check manual trigger from the app
      if (motorActive) {
        Serial.println("Manual water command detected!");
        triggerWatering = true;
      } 
      // Check 2: Check daily scheduled watering time
      else if (dailyEnabled) {
        DateTime nowTime = rtc.now();
        char currentTime[6];
        sprintf(currentTime, "%02d:%02d", nowTime.hour(), nowTime.minute());
        
        // Match HH:MM and only trigger once per day
        if (dailyTime.substring(0, 5) == String(currentTime) &&
            nowTime.day() != lastDailyWateringDay) {
          Serial.println("Daily watering schedule match!");
          lastDailyWateringDay = nowTime.day(); // Mark today as done
          triggerWatering = true;
        }
      }

      if (triggerWatering && !motorRunning) {
        Serial.println("Triggering watering cycle!");

        // 1. Reset motor_active in DB FIRST (this HTTP call takes ~1-2s)
        if (motorActive) {
          updateDatabaseMotorActive(false);
        }

        // 2. Start timer AFTER the HTTP call so duration is accurate
        motorDuration = (unsigned long)(duration) * 1000UL;
        motorStartTime = millis();
        motorRunning = true;

        // 3. Turn relay ON last
        pinMode(motorRelayPin, OUTPUT);
        digitalWrite(motorRelayPin, LOW);
        Serial.print("Relay ON for ");
        Serial.print(duration);
        Serial.println("s (non-blocking).");
      } else if (!triggerWatering) {
        Serial.println("No watering triggers active.");
      }
    }
  } else {
    Serial.print("Error GET response: ");
    Serial.println(http.getString());
  }
  http.end();
  client.stop(); // Explicitly free SSL memory
}

// ==========================================
// RESET MOTOR TRIGGER IN DATABASE
// ==========================================
void updateDatabaseMotorActive(bool active) {
  WiFiClientSecure client;
  client.setInsecure(); // Bypass SSL validation
  HTTPClient http;
  String url = String(supabaseUrl) + "/rest/v1/profiles?id=eq." + String(userId);
  http.begin(client, url);
  http.setReuse(false); // Fix memory leak
  
  http.addHeader("apikey", supabaseKey);
  http.addHeader("Authorization", "Bearer " + String(supabaseKey));
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Prefer", "return=minimal");

  #if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
  #else
  DynamicJsonDocument doc(256);
  #endif
  doc["motor_active"] = active;

  String jsonPayload;
  serializeJson(doc, jsonPayload);

  int httpResponseCode = http.PATCH(jsonPayload); // PATCH updates target fields
  Serial.print("PATCH (Motor Reset) Response Code: ");
  Serial.println(httpResponseCode);
  http.end();
  client.stop();
}

// ==========================================
// RESET WIFI RESET FLAG IN DATABASE
// ==========================================
void updateDatabaseWifiReset(bool reset) {
  WiFiClientSecure client;
  client.setInsecure(); // Bypass SSL validation
  HTTPClient http;
  String url = String(supabaseUrl) + "/rest/v1/profiles?id=eq." + String(userId);
  http.begin(client, url);
  http.setReuse(false);
  
  http.addHeader("apikey", supabaseKey);
  http.addHeader("Authorization", "Bearer " + String(supabaseKey));
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Prefer", "return=minimal");

  #if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
  #else
  DynamicJsonDocument doc(256);
  #endif
  doc["wifi_reset"] = reset;

  String jsonPayload;
  serializeJson(doc, jsonPayload);

  int httpResponseCode = http.PATCH(jsonPayload); // PATCH updates target fields
  Serial.print("PATCH (WiFi Reset Update) Response Code: ");
  Serial.println(httpResponseCode);
  http.end();
  client.stop();
}

// ==========================================
// SEND TELEMETRY TO DATABASE
// ==========================================
void sendTelemetryData() {
  WiFiClientSecure client;
  client.setInsecure(); // Bypass SSL validation
  HTTPClient http;
  String url = String(supabaseUrl) + "/rest/v1/telemetry";
  http.begin(client, url);
  http.setReuse(false); // Prevent -1 connection leak

  http.addHeader("apikey", supabaseKey);
  http.addHeader("Authorization", "Bearer " + String(supabaseKey));
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Prefer", "return=minimal");

  // --- ACCURATE BATTERY CALCULATION ---
  int batteryRaw = analogRead(batteryPin);

  // 1. Convert the raw ADC reading (0-4095) to actual voltage at the pin (0-3.3V)
  float pinVoltage = (batteryRaw / 4095.0) * 3.3;
  
  // 2. Multiply by 2 because our two identical 100k resistors cut the voltage exactly in half
  float batteryVoltage = pinVoltage * 2.0;
  
  // 3. Convert to percentage (18650s are full at 4.2V and empty around 3.2V)
  int batteryPercentage = 0;
  if (batteryVoltage >= 4.2) {
    batteryPercentage = 100;
  } else if (batteryVoltage <= 3.2) {
    batteryPercentage = 0;
  } else {
    batteryPercentage = (int)(((batteryVoltage - 3.2) / (4.2 - 3.2)) * 100);
  }
  
  // Ensure it never sends a weird number above 100 or below 0
  batteryPercentage = constrain(batteryPercentage, 0, 100);
  
  Serial.print("Battery Voltage: ");
  Serial.print(batteryVoltage);
  Serial.print("V (");
  Serial.print(batteryPercentage);
  Serial.println("%)");
  // ------------------------------------

  bool motorActive = digitalRead(motorRelayPin) == LOW; // Check current relay state

  // --- SOIL MOISTURE READING ---
  int soilMoistureRaw = -1; // -1 means disabled
  if (soilSensorEnabled) {
    digitalWrite(soilPowerPin, HIGH); // Power up sensor
    delay(20); // Wait for sensor to stabilize
    soilMoistureRaw = analogRead(soilSensorPin);
    digitalWrite(soilPowerPin, LOW); // Power down sensor
    Serial.print("Soil Moisture Raw: ");
    Serial.println(soilMoistureRaw);
  } else {
    Serial.println("Soil Moisture Sensor is DISABLED by user.");
  }
  // -----------------------------

  // --- Solar Voltage Reading (Voltage Divider 47k + 47k) ---
  int solarRaw = analogRead(solarPin);
  float solarMeasured = (solarRaw / 4095.0) * 3.3; 
  float solarVoltage = solarMeasured * 2.0; // Because it's halved by 47k+47k divider
  
  bool isCharging = (solarVoltage > 1.0); // Assume charging if solar is generating anything
  
  Serial.print("Solar Voltage: ");
  Serial.print(solarVoltage);
  Serial.println("V");
  
  // Build JSON
  #if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
  #else
  DynamicJsonDocument doc(512);
  #endif

  doc["device_id"] = deviceId;
  doc["user_id"] = userId;
  doc["battery_percentage"] = batteryPercentage;
  doc["is_charging"] = isCharging; // Set by actual solar voltage now!
  doc["solar_voltage"] = solarVoltage;
  doc["motor_active"] = motorActive;
  if (soilSensorEnabled) {
    doc["soil_moisture"] = soilMoistureRaw;
  } else {
    doc["soil_moisture"] = nullptr; // Send null to clear it from app UI
  }

  String jsonPayload;
  serializeJson(doc, jsonPayload);

  int httpResponseCode = http.POST(jsonPayload);
  Serial.print("POST (Telemetry Upload) Response Code: ");
  Serial.println(httpResponseCode);

  if (httpResponseCode == 201 || httpResponseCode == 200) {
    Serial.println("Telemetry successfully uploaded.");
  } else {
    Serial.print("Error POST response: ");
    Serial.println(http.getString());
  }
  http.end();
  client.stop();
}