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

// --- NTP Time Setup ---
const long gmtOffset_sec = 19800;  // Adjust to your local timezone (e.g. India GMT+5:30 is 19800)
const int daylightOffset_sec = 0;

void setup() {
  Serial.begin(115200);
  delay(500);
  
  Serial.println("\n-------------------------------------------");
  Serial.println("ESP32 Solar Flora - Continuous Mode");
  Serial.println("-------------------------------------------");

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
      Serial.println("\nNTP sync timed out. Continuing anyway.");
    }
  }
}

void loop() {
  // Reconnect WiFi if dropped
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi lost. Reconnecting...");
    connectWiFi();
    return;
  }

  unsigned long now = millis();

  // --- Non-blocking motor shutoff check ---
  if (motorRunning && (now - motorStartTime >= motorDuration)) {
    pinMode(motorRelayPin, INPUT); // Release relay (turns OFF)
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
          
          // Match HH:MM and only trigger once per day
          if (dailyTime.substring(0, 5) == String(currentTime) &&
              timeinfo.tm_mday != lastDailyWateringDay) {
            Serial.println("Daily watering schedule match!");
            lastDailyWateringDay = timeinfo.tm_mday; // Mark today as done
            triggerWatering = true;
          }
        }
      }

      if (triggerWatering && !motorRunning) {
        Serial.println("Triggering watering cycle!");
        motorDuration = duration * 1000UL; // Convert seconds to milliseconds
        motorStartTime = millis();
        motorRunning = true;
        pinMode(motorRelayPin, OUTPUT);   // Take control of the pin
        digitalWrite(motorRelayPin, LOW); // Relay ON (Active Low)
        Serial.print("Relay ON for ");
        Serial.print(duration);
        Serial.println("s (non-blocking).");

        // Reset motor_active in DB immediately so we don't re-trigger
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

  // Build JSON
  #if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
  #else
  DynamicJsonDocument doc(512);
  #endif

  doc["device_id"] = deviceId;
  doc["user_id"] = userId;
  doc["battery_percentage"] = batteryPercentage;
  doc["is_charging"] = false; // Charging state determined by Flutter app from % trend
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