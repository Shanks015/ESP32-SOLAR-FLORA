#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <WiFiManager.h> // Include WiFiManager Library
#include "time.h"

// --- Network & Supabase Credentials ---
#include "secrets.h" // secrets.h no longer needs SSID and Password!

const char* deviceId = "ESP32_SOLAR_001";

// --- Hardware Pins ---
const int batteryPin = 34;   
const int chargingPin = 33;   // Moved from GPIO 35 (no pull-up support) to GPIO 33
const int motorRelayPin = 4; // Assuming GPIO 4 for your water pump relay

// --- Deep Sleep Config ---
#define uS_TO_S_FACTOR 1000000ULL  /* Conversion factor for micro seconds to seconds */
int sleepInterval = 600;           /* Default sleep time in seconds - 10 minutes */

// --- NTP Time Setup ---
const long gmtOffset_sec = 19800;  // Adjust to your local timezone (e.g. India GMT+5:30 is 19800)
const int daylightOffset_sec = 0;

void setup() {
  Serial.begin(115200);
  delay(500); // Wait for serial to initialize
  
  Serial.println("\n-------------------------------------------");
  Serial.println("ESP32 WOKE UP from Deep Sleep Mode!");
  Serial.println("-------------------------------------------");

  pinMode(chargingPin, INPUT_PULLUP); // Pull-up so CHRG pin reads HIGH when not charging
  pinMode(motorRelayPin, INPUT); // High-impedance state (truly OFF for 5V relays)

  // 1. Connect to WiFi using WiFiManager
  connectWiFi();

  if (WiFi.status() == WL_CONNECTED) {
    // 2. Synchronize Clock with Internet NTP Time
    configTime(gmtOffset_sec, daylightOffset_sec, "pool.ntp.org", "time.nist.gov");
    Serial.println("Synchronizing internet time...");
    struct tm timeinfo;
    int ntpRetries = 0;
    while (!getLocalTime(&timeinfo) && ntpRetries < 10) {
      Serial.print(".");
      delay(500);
      ntpRetries++;
    }
    if (ntpRetries < 10) {
      Serial.println(&timeinfo, "\nTime synchronized: %Y-%m-%d %H:%M:%S");
    } else {
      Serial.println("\nNTP sync timed out. Continuing without time sync.");
    }

    // 3. Process scheduled/manual watering commands
    processWateringLogic();

    delay(1000); // 1-second delay to prevent HTTPS buffer overflow

    // 4. Send telemetry update
    sendTelemetryData();
  } else {
    Serial.println("Skipping network actions because WiFi configuration failed or timed out.");
  }

  // 5. Enter Deep Sleep (WiFi and CPU turn off completely)
  Serial.print("Entering Deep Sleep for ");
  Serial.print(sleepInterval);
  Serial.println(" seconds. Goodnight!");
  
  esp_sleep_enable_timer_wakeup(sleepInterval * uS_TO_S_FACTOR);
  esp_deep_sleep_start();
}

void loop() {
  // Loop is never reached in Deep Sleep mode since setup() runs once per wakeup
}

// ==========================================
// WIFI CONNECT VIA WIFIMANAGER PORTAL
// ==========================================
void connectWiFi() {
  WiFiManager wm;

  // Set timeout of 120 seconds (2 mins) to save battery if router is off
  wm.setConfigPortalTimeout(120); 

  // Try to connect to saved credentials, or start captive AP named "Solar_Flora_Config"
  Serial.println("Connecting to WiFi via WiFiManager...");
  bool res = wm.autoConnect("Solar_Flora_Config");

  if (!res) {
    Serial.println("WiFi configuration failed or portal timed out.");
  } else {
    Serial.println("Connected to WiFi successfully!");
  }
}

// ==========================================
// PROCESS MANUAL COMMANDS AND SCHEDULES
// ==========================================
void processWateringLogic() {
  HTTPClient http;
  
  // Fetch columns needed for schedules and controls
  String url = String(supabaseUrl) + "/rest/v1/profiles?select=motor_active,daily_watering_enabled,daily_watering_time,watering_duration,sleep_interval&id=eq." + String(userId);
  http.begin(url);
  
  http.addHeader("apikey", supabaseKey);
  http.addHeader("Authorization", "Bearer " + String(supabaseKey));

  int httpResponseCode = http.GET();
  Serial.print("GET (Command Check) Response Code: ");
  Serial.println(httpResponseCode);

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
      sleepInterval = doc[0]["sleep_interval"] | 600; // Parse the dynamically configured sleep interval

      bool triggerWatering = false;

      // Check 1: Check manual trigger from the app
      if (motorActive) {
        Serial.println("Manual water command detected!");
        triggerWatering = true;
      } 
      // Check 2: Check daily scheduled watering time
      else if (dailyEnabled) {
        struct tm timeinfo;
        if (getLocalTime(&timeinfo)) {
          char currentTime[6];
          sprintf(currentTime, "%02d:%02d", timeinfo.tm_hour, timeinfo.tm_min);
          
          // Match HH:MM
          if (dailyTime.substring(0, 5) == String(currentTime)) {
            Serial.println("Daily watering schedule match!");
            triggerWatering = true;
          }
        }
      }

      if (triggerWatering) {
        Serial.println("Triggering watering cycle!");
        pinMode(motorRelayPin, OUTPUT);   // Take control of the pin
        digitalWrite(motorRelayPin, LOW); // Relay ON (Active Low)
        
        // Water for the configured duration (in seconds)
        delay(duration * 1000);
        
        pinMode(motorRelayPin, INPUT);    // Release control (Relay turns OFF)
        Serial.println("Watering cycle complete.");

        // If it was a manual click, reset it back to false in the database
        if (motorActive) {
          updateDatabaseMotorActive(false);
        }
      } else {
        Serial.println("No watering triggers active.");
      }
    }
  } else {
    Serial.print("Error GET response: ");
    Serial.println(http.getString());
  }
  http.end();
}

// ==========================================
// RESET MOTOR TRIGGER IN DATABASE
// ==========================================
void updateDatabaseMotorActive(bool active) {
  HTTPClient http;
  String url = String(supabaseUrl) + "/rest/v1/profiles?id=eq." + String(userId);
  http.begin(url);
  
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
}

// ==========================================
// SEND TELEMETRY TO DATABASE
// ==========================================
void sendTelemetryData() {
  HTTPClient http;
  String url = String(supabaseUrl) + "/rest/v1/telemetry";
  http.begin(url);

  http.addHeader("apikey", supabaseKey);
  http.addHeader("Authorization", "Bearer " + String(supabaseKey));
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Prefer", "return=minimal");

  // --- ACCURATE BATTERY CALCULATION ---
  int batteryRaw = analogRead(batteryPin);
  
  Serial.print("DEBUG Raw ADC: "); Serial.println(batteryRaw);

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

  bool isCharging = digitalRead(chargingPin) == LOW; // TP4056 CHRG pin is LOW when charging
  bool motorActive = digitalRead(motorRelayPin) == LOW; // Check current relay state

  // Build JSON
  #if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
  #else
  DynamicJsonDocument doc(512);
  #endif

  doc["device_id"] = deviceId;
  doc["user_id"] = userId;
  doc["battery_percentage"] = batteryPercentage;
  doc["is_charging"] = isCharging;
  doc["motor_active"] = motorActive;

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
}