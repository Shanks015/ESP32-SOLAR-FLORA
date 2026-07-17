#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h> // Include secure client library
#include <ArduinoJson.h>
#include <Wire.h>
#include <RTClib.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

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

// --- RTC Setup ---
RTC_DS3231 rtc;

// --- BLE Configuration Globals ---
BLEServer* pServer = NULL;
BLECharacteristic* pWriteCharacteristic = NULL;
BLECharacteristic* pStatusCharacteristic = NULL;
bool bleConfigCompleted = false;
bool deviceConnected = false;

void setup() {
  Serial.begin(115200);
  delay(500);
  
  Serial.println("\n-------------------------------------------");
  Serial.println("ESP32 Solak - Continuous Mode");
  Serial.println("-------------------------------------------");

  pinMode(motorRelayPin, INPUT); // High-impedance state (truly OFF for 5V relays)

  // 1. Connect to WiFi using WiFiManager
  connectWiFi();

  // 2. Initialize RTC
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

// --- Persistent Credentials Storage ---
Preferences preferences;

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

// --- BLE Callbacks ---
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define WRITE_UUID          "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define STATUS_UUID         "beb5483e-36e1-4688-b7f5-ea07361b26a9"

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("App connected via Bluetooth!");
    }
    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("App disconnected from Bluetooth!");
      // Restart advertising so other attempts can connect
      BLEDevice::startAdvertising();
    }
};

class BLEWiFiCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String value = pCharacteristic->getValue().c_str();
      if (value.length() > 0) {
        Serial.println("Received WiFi configuration over BLE!");
        
        #if ARDUINOJSON_VERSION_MAJOR >= 7
        JsonDocument doc;
        #else
        DynamicJsonDocument doc(512);
        #endif
        DeserializationError error = deserializeJson(doc, value.c_str());
        
        if (!error) {
          String ssid = doc["ssid"] | "";
          String pass = doc["pass"] | "";
          
          if (ssid.length() > 0) {
            Serial.print("Connecting to WiFi SSID: ");
            Serial.println(ssid);
            
            pStatusCharacteristic->setValue("CONNECTING");
            pStatusCharacteristic->notify();
            
            WiFi.disconnect();
            WiFi.begin(ssid.c_str(), pass.c_str());
            
            int retries = 0;
            while (WiFi.status() != WL_CONNECTED && retries < 30) {
              delay(500);
              Serial.print(".");
              retries++;
            }
            
            if (WiFi.status() == WL_CONNECTED) {
              Serial.println("\nWiFi connected successfully!");
              saveWiFiCredentials(ssid, pass);
              pStatusCharacteristic->setValue("CONNECTED");
              pStatusCharacteristic->notify();
              delay(1000);
              bleConfigCompleted = true;
            } else {
              Serial.println("\nWiFi connection failed!");
              pStatusCharacteristic->setValue("FAILED");
              pStatusCharacteristic->notify();
            }
          }
        }
      }
    }
};

void startBLEOnboarding() {
  Serial.println("Starting BLE Onboarding Mode...");
  
  BLEDevice::init("Solak_Config");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  
  BLEService *pService = pServer->createService(SERVICE_UUID);
  
  pWriteCharacteristic = pService->createCharacteristic(
    WRITE_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pWriteCharacteristic->setCallbacks(new BLEWiFiCallbacks());
  
  pStatusCharacteristic = pService->createCharacteristic(
    STATUS_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pStatusCharacteristic->addDescriptor(new BLE2902());
  pStatusCharacteristic->setValue("IDLE");
  
  pService->start();
  
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  // helper for iOS connection speed
  pAdvertising->setMinPreferred(0x12);
  
  BLEDevice::startAdvertising();
  Serial.println("BLE advertising as 'Solak_Config'. Connect using the mobile app.");
  
  // Wait until configuration is successfully completed
  while (!bleConfigCompleted) {
    delay(500);
  }
  
  // Clean up BLE to free up memory and radio
  Serial.println("Stopping BLE config server...");
  BLEDevice::deinit(true);
}

void connectWiFi() {
  String ssid = "";
  String password = "";
  loadWiFiCredentials(ssid, password);
  
  if (ssid.length() > 0) {
    Serial.print("Connecting to saved WiFi: ");
    Serial.println(ssid);
    WiFi.begin(ssid.c_str(), password.c_str());
    
    int retries = 0;
    while (WiFi.status() != WL_CONNECTED && retries < 20) {
      delay(500);
      Serial.print(".");
      retries++;
    }
    
    if (WiFi.status() == WL_CONNECTED) {
      Serial.println("\nConnected to saved WiFi successfully!");
      return;
    } else {
      Serial.println("\nFailed to connect to saved WiFi.");
    }
  }
  
  // If no credentials or connection failed, enter BLE Onboarding
  startBLEOnboarding();
}

// ==========================================
// PROCESS MANUAL COMMANDS AND SCHEDULES
// ==========================================
void processWateringLogic() {
  WiFiClientSecure client;
  client.setInsecure(); // Bypass SSL certificate validation to prevent connection code -1
  HTTPClient http;
  
  // Fetch columns needed for schedules and controls
  String url = String(supabaseUrl) + "/rest/v1/profiles?select=motor_active,daily_watering_enabled,daily_watering_time,watering_duration,sleep_interval&id=eq." + String(userId);
  http.begin(client, url);
  
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
  WiFiClientSecure client;
  client.setInsecure(); // Bypass SSL validation
  HTTPClient http;
  String url = String(supabaseUrl) + "/rest/v1/telemetry";
  http.begin(client, url);

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