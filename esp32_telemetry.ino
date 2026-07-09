#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>

// --- Network & Supabase Credentials ---
#include "secrets.h"

const char* deviceId = "ESP32_SOLAR_001";

// --- Hardware Pins ---
const int batteryPin = 34;   
const int chargingPin = 35;  
const int motorRelayPin = 4; // Assuming GPIO 4 for your water pump relay

// --- Timers ---
unsigned long previousTelemetryTime = 0;
const long telemetryInterval = 30000; // Send data every 30 seconds

unsigned long previousPollTime = 0;
const long pollInterval = 3000; // Check for "Water Now" button every 3 seconds

void setup() {
  Serial.begin(115200);
  
  pinMode(chargingPin, INPUT);
  pinMode(motorRelayPin, OUTPUT);
  digitalWrite(motorRelayPin, HIGH); // Relay OFF by default (Active Low)

  // Connect to WiFi
  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nConnected to WiFi!");
}

void loop() {
  unsigned long currentMillis = millis();

  // 1. FAST LOOP: Check if the user pressed "Water Now" in the app
  if (currentMillis - previousPollTime >= pollInterval) {
    previousPollTime = currentMillis;
    checkForWaterCommand();
  }

  // 2. SLOW LOOP: Send battery & solar data to the app
  if (currentMillis - previousTelemetryTime >= telemetryInterval) {
    previousTelemetryTime = currentMillis;
    sendTelemetryData();
  }
}

// ==========================================
// FUNCTION 1: CHECK FOR APP COMMANDS (GET)
// ==========================================
void checkForWaterCommand() {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    
    // Specifically ask Supabase for the motor_active status of YOUR profile
    String url = String(supabaseUrl) + "/rest/v1/profiles?select=motor_active&id=eq." + String(userId);
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
      
      // Parse the JSON array returned by Supabase: [{"motor_active":true}]
      #if ARDUINOJSON_VERSION_MAJOR >= 7
      JsonDocument doc;
      #else
      DynamicJsonDocument doc(512);
      #endif
      
      DeserializationError error = deserializeJson(doc, payload);
      
      if (!error) {
        if (doc.size() > 0) {
          bool shouldWater = doc[0]["motor_active"];
          if (shouldWater) {
            Serial.println("COMMAND RECEIVED: Turning Pump ON!");
            digitalWrite(motorRelayPin, LOW); // Trigger Relay (Active Low)
          } else {
            Serial.println("Pump Command: OFF.");
            digitalWrite(motorRelayPin, HIGH); // Turn off Relay
          }
        } else {
          Serial.println("Warning: Profile row not found for this User ID!");
        }
      } else {
        Serial.print("JSON Deserialization Error: ");
        Serial.println(error.c_str());
      }
    } else {
      Serial.print("Error GET response: ");
      Serial.println(http.getString());
    }
    http.end();
  }
}

// ==========================================
// FUNCTION 2: SEND TELEMETRY (POST)
// ==========================================
void sendTelemetryData() {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    
    String url = String(supabaseUrl) + "/rest/v1/telemetry";
    http.begin(url);
    
    http.addHeader("apikey", supabaseKey);
    http.addHeader("Authorization", "Bearer " + String(supabaseKey));
    http.addHeader("Content-Type", "application/json");
    http.addHeader("Prefer", "return=minimal");

    // Read Sensors
    int batteryRaw = analogRead(batteryPin);
    int batteryPercentage = map(batteryRaw, 0, 4095, 0, 100); 
    bool isCharging = digitalRead(chargingPin) == HIGH;
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
      Serial.println("Telemetry successfully sent to App.");
    } else {
      Serial.print("Error POST response: ");
      Serial.println(http.getString());
    }
    http.end();
  }
}