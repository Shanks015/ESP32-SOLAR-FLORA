# Solak: Smart Solar Plant Care System 🌱☀️

Solak is a completely off-grid, automated plant watering and monitoring system built with an ESP32 and controlled remotely via a beautiful Flutter mobile application. It relies entirely on solar energy, leveraging a 18650 lithium battery, TP4056 charging module, and deep-sleep mechanisms to ensure it can run indefinitely without external power.

## Key Features

- **☀️ 100% Solar Powered**: Uses a 6V solar panel and a TP4056 charging module to keep the internal 18650 battery charged indefinitely.
- **📱 Premium Flutter App**: A gorgeous, dark-themed mobile app to monitor real-time telemetry, toggle sensors, and trigger manual watering.
- **💧 Automated Watering Engine**: Uses a 5V relay and water pump to automate daily watering schedules (persisted via an onboard DS3231 RTC module).
- **☁️ Supabase Cloud Backend**: All telemetry and user commands are synchronized through a PostgreSQL Supabase database using REST APIs.
- **🔋 Intelligent Power Management**: The ESP32 goes into deep sleep between checks to conserve power. It measures the battery percentage and calculates the exact live solar voltage via a voltage divider on the VP pin (GPIO 36).
- **🌱 Soil Moisture Sensing**: Integrated soil moisture probe powered only during reads (via GPIO 32) to prevent electrolytic corrosion, returning precise analog readings.
- **🛜 SoftAP Provisioning**: Headless Wi-Fi setup allows the user to configure the device's network credentials through a built-in captive portal.

## Hardware Stack

- **Microcontroller**: ESP32 Development Board
- **Power**: 6V Solar Panel + TP4056 Charger + 18650 Li-ion Battery
- **Timekeeping**: DS3231 RTC Module (I2C)
- **Actuator**: 5V Relay Module + Submersible Mini Water Pump
- **Sensor**: Analog Soil Moisture Sensor
- **Voltage Divider**: 2x 47kΩ resistors (for solar voltage measurement up to 6.6V safely)

## Hardware Pinout Reference

| Component                 | ESP32 Pin / Detail                                 |
| ------------------------- | -------------------------------------------------- |
| **I2C RTC (DS3231)**      | `SDA` ➔ GPIO 21, `SCL` ➔ GPIO 22                    |
| **Water Pump Relay**      | `IN` ➔ GPIO 4                                       |
| **Battery Voltage (ADC)** | `AOUT` ➔ GPIO 34 (via 100kΩ/100kΩ voltage divider)  |
| **Solar Voltage (ADC)**   | `AOUT` ➔ GPIO 36 (via 47kΩ/47kΩ voltage divider)    |
| **Moisture Sensor Power** | `VCC` ➔ GPIO 32 (power-gated to prevent corrosion) |
| **Moisture Sensor Data**  | `AOUT` ➔ GPIO 35                                    |
| **TP4056 Charging State** | `CHRG` ➔ GPIO 33 (Optional physical indicator)      |

## Software Stack

- **Firmware**: C++ (Arduino IDE) with `ArduinoJson`, `RTClib`, and `HTTPClient`.
- **Mobile App**: Flutter (Dart) using `supabase_flutter` for real-time Postgres subscriptions.
- **Database**: Supabase (PostgreSQL).

## Setup & Installation

### 1. Database (Supabase)
Create a new Supabase project and execute the required SQL schema to set up the `profiles` and `telemetry` tables. Make sure to include the `solar_voltage` and `soil_moisture` columns. 

### 2. Firmware (ESP32)
1. Rename `secrets_template.h` to `secrets.h` and populate it with your Supabase REST URL and anon key.
2. Flash `esp32_telemetry.ino` to your ESP32. 
3. On first boot, the ESP32 will host a Wi-Fi network named **Solak_Setup**  Connect to this network using the mobile app to provision your home Wi-Fi credentials.

### 3. Mobile App (Flutter)
1. Navigate to the root directory and run `flutter pub get`.
2. Update the Supabase initialization keys in `lib/main.dart` with your project URL and anon key.
3. Build the app using `flutter build apk --release` (for Android) or run it directly on an emulator.

---
*Built with ❤️ to keep plants happy, healthy, and hydrated.*
