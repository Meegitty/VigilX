import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? dataCharacteristic;

  bool get isConnected => connectedDevice != null;

  // 🔴 REPLACE THESE WITH YOUR REAL UUIDs
  final String serviceUUID = "12345678-1234-1234-1234-1234567890ab";
  final String dataCharUUID = "abcd1234-1234-1234-1234-1234567890ab";

  final String deviceName = "ESP32_ACCIDENT_MONITOR";

  Future<void> startScanAndConnect(
    Function(Map<String, dynamic>) onAccident, {
    void Function(bool connected)? onConnectionChanged,
  }) async {

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 5),
    );

    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {

        if (r.device.platformName == deviceName ||
            r.advertisementData.localName == deviceName) {

          await FlutterBluePlus.stopScan();

          connectedDevice = r.device;
          onConnectionChanged?.call(true);

          await connectedDevice!.connect(
            license: License.free,
            mtu: null,
          );

          await discoverServices(onAccident);
          break;
        }
      }
    });
  }

  Future<void> discoverServices(
      Function(Map<String, dynamic>) onAccident) async {

    List<BluetoothService> services =
        await connectedDevice!.discoverServices();

    for (var service in services) {

      if (service.uuid.toString().toLowerCase() ==
          serviceUUID.toLowerCase()) {

        for (var characteristic in service.characteristics) {

          if (characteristic.uuid.toString().toLowerCase() ==
              dataCharUUID.toLowerCase()) {

            dataCharacteristic = characteristic;

            await dataCharacteristic!.setNotifyValue(true);

            listenToAccident(onAccident);
          }
        }
      }
    }
  }

  void listenToAccident(
      Function(Map<String, dynamic>) onAccident) {

    dataCharacteristic!.value.listen((value) {

      if (value.isNotEmpty) {

        String jsonString = utf8.decode(value);

        print("Received: $jsonString");

        try {
          Map<String, dynamic> accidentData =
              jsonDecode(jsonString);

          if (accidentData["accident"] == "YES") {
            onAccident(accidentData);
          }

        } catch (e) {
          print("JSON parse error: $e");
        }
      }
    });
  }

  Future<void> disconnect({void Function(bool connected)? onConnectionChanged}) async {
    await connectedDevice?.disconnect();
    connectedDevice = null;
    dataCharacteristic = null;
    onConnectionChanged?.call(false);
  }
}