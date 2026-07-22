import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_fonts/google_fonts.dart';

class WifiConfigDialog extends StatefulWidget {
  const WifiConfigDialog({Key? key}) : super(key: key);

  @override
  State<WifiConfigDialog> createState() => _WifiConfigDialogState();
}

class _WifiConfigDialogState extends State<WifiConfigDialog> {
  // BLE UUIDs matching the ESP32 code
  final String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String writeUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  final String statusUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a9";

  BluetoothDevice? _connectedDevice;
  BluetoothService? _targetService;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _statusCharacteristic;

  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _statusMessage = "IDLE"; // IDLE, CONNECTING, CONNECTED, FAILED
  bool _isSending = false;

  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _statusSubscription;
  BluetoothAdapterState _bluetoothState = BluetoothAdapterState.unknown;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  @override
  void initState() {
    super.initState();
    // Check initial state synchronously
    _bluetoothState = FlutterBluePlus.adapterStateNow;
    // Subscribe to Bluetooth adapter state changes
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (mounted) {
        setState(() {
          _bluetoothState = state;
          if (state != BluetoothAdapterState.on) {
            _scanResults.clear();
          }
        });
      }
    });
    _startScan();
  }

  @override
  void dispose() {
    _adapterStateSubscription?.cancel();
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _statusSubscription?.cancel();
    _ssidController.dispose();
    _passwordController.dispose();
    if (_connectedDevice != null) {
      _connectedDevice!.disconnect();
    }
    super.dispose();
  }

  Future<void> _requestEnableBluetooth() async {
    if (Platform.isAndroid) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (e) {
        print("Error turning on Bluetooth: $e");
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please turn on Bluetooth to connect to the device"),
          backgroundColor: Color(0xFFBA1A1A),
        ),
      );
    }
  }

  Future<void> _startScan() async {
    // Request Bluetooth and Location checks
    if (await FlutterBluePlus.isSupported == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Bluetooth is not supported on this device")),
      );
      return;
    }

    final adapterState = FlutterBluePlus.adapterStateNow;
    if (adapterState != BluetoothAdapterState.on) {
      await _requestEnableBluetooth();
      return;
    }

    setState(() {
      _scanResults.clear();
      _isScanning = true;
    });

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          // Filter to show devices with "Solak" in name, or all devices if name is empty
          _scanResults = results.where((r) => r.device.platformName.isNotEmpty).toList();
        });
      }
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      print("Scan error: $e");
    }

    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    final adapterState = FlutterBluePlus.adapterStateNow;
    if (adapterState != BluetoothAdapterState.on) {
      await _requestEnableBluetooth();
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    try {
      await device.connect(license: License.nonprofit, autoConnect: false);
      _connectedDevice = device;

      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && mounted) {
          setState(() {
            _isConnected = false;
            _isConnecting = false;
            _statusMessage = "IDLE";
          });
        }
      });

      // Discover Services
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
          _targetService = service;
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase() == writeUuid.toLowerCase()) {
              _writeCharacteristic = char;
            }
            if (char.uuid.toString().toLowerCase() == statusUuid.toLowerCase()) {
              _statusCharacteristic = char;
            }
          }
        }
      }

      if (_writeCharacteristic != null && _statusCharacteristic != null) {
        // Setup status notifications
        await _statusCharacteristic!.setNotifyValue(true);
        _statusSubscription = _statusCharacteristic!.lastValueStream.listen((value) {
          if (value.isNotEmpty && mounted) {
            String status = utf8.decode(value);
            setState(() {
              _statusMessage = status;
              if (status == "CONNECTED") {
                _isSending = false;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("WiFi configured and connected successfully!"),
                    backgroundColor: Color(0xFF41B883),
                  ),
                );
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) Navigator.of(context).pop();
                });
              } else if (status == "FAILED") {
                _isSending = false;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("WiFi connection failed. Check your SSID and Password."),
                    backgroundColor: Color(0xFFBA1A1A),
                  ),
                );
              }
            });
          }
        });

        setState(() {
          _isConnected = true;
          _isConnecting = false;
        });
      } else {
        throw Exception("Target BLE characteristics not found on device.");
      }
    } catch (e) {
      print("Connection error: $e");
      setState(() {
        _isConnecting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to connect: $e")),
      );
    }
  }

  Future<void> _sendConfig() async {
    if (!_formKey.currentState!.validate() || _writeCharacteristic == null) return;

    setState(() {
      _isSending = true;
      _statusMessage = "CONNECTING";
    });

    final configPayload = jsonEncode({
      "ssid": _ssidController.text.trim(),
      "pass": _passwordController.text,
    });

    try {
      await _writeCharacteristic!.write(utf8.encode(configPayload));
    } catch (e) {
      setState(() {
        _isSending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to send credentials: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF16221A) : Colors.white;
    final primaryColor = const Color(0xFF4F635B);
    final textColor = isDark ? const Color(0xFFE0EAE1) : const Color(0xFF141E17);

    return Dialog(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        padding: const EdgeInsets.all(24),
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Device Onboarding",
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                ],
              ),
              const Divider(),
              const SizedBox(height: 16),

              if (!_isConnected) ...[
                Text(
                  "Select your Solak device to connect via Bluetooth:",
                  style: GoogleFonts.manrope(color: textColor, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _bluetoothState != BluetoothAdapterState.on
                      ? InkWell(
                          onTap: _requestEnableBluetooth,
                          borderRadius: BorderRadius.circular(12),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.bluetooth_disabled,
                                    color: Color(0xFFBA1A1A),
                                    size: 32,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Bluetooth is turned off. Tap to turn on Bluetooth.",
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.manrope(
                                      color: const Color(0xFFBA1A1A),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : _isConnecting
                          ? const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation(Color(0xFF4F635B)),
                              ),
                            )
                          : _scanResults.isEmpty
                              ? Center(
                                  child: Text(
                                    _isScanning ? "Scanning..." : "No devices found.",
                                    style: GoogleFonts.manrope(color: Colors.grey),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _scanResults.length,
                                  itemBuilder: (context, index) {
                                    final result = _scanResults[index];
                                    final name = result.device.platformName;
                                    return ListTile(
                                      leading: const Icon(Icons.bluetooth),
                                      title: Text(
                                        name,
                                        style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 14),
                                      ),
                                      subtitle: Text(result.device.remoteId.toString(), style: const TextStyle(fontSize: 11)),
                                      onTap: () => _connectToDevice(result.device),
                                    );
                                  },
                                ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _isScanning ? null : _startScan,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text("SCAN", style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ] else ...[
                Text(
                  "Connected to ${(_connectedDevice?.platformName.isNotEmpty ?? false) ? _connectedDevice?.platformName : 'Solak Device'}",
                  style: GoogleFonts.manrope(color: const Color(0xFF41B883), fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 16),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _ssidController,
                        decoration: InputDecoration(
                          labelText: "WiFi SSID (Name)",
                          labelStyle: GoogleFonts.manrope(fontSize: 13),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? "SSID required" : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: "WiFi Password",
                          labelStyle: GoogleFonts.manrope(fontSize: 13),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_isSending) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFF4F635B))),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        "Status: $_statusMessage",
                        style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.bold),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: _isSending
                          ? null
                          : () {
                              _connectedDevice?.disconnect();
                            },
                      child: Text("Disconnect", style: GoogleFonts.manrope(color: Colors.red)),
                    ),
                    ElevatedButton(
                      onPressed: _isSending ? null : _sendConfig,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: Text("Send Setup", style: GoogleFonts.manrope(fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
