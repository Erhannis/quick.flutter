import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:quick_blue/quick_blue.dart';
import 'package:quick_blue/src/method_channel_quick_blue.dart';

import 'models.dart';

export 'method_channel_quick_blue.dart';
export 'models.dart';

typedef QuickLogger = Logger;

typedef XString = String; //DUMMY

typedef OnConnectionChanged = void Function(
    String deviceId, BlueConnectionState state);

typedef OnServiceDiscovered = void Function(
    String deviceId, XString serviceId, List<XString> characteristicIds);

typedef OnValueChanged = void Function(
    String deviceId, XString serviceId, XString characteristicId, Uint8List value);

typedef OnWroteCharacteristic = void Function(
    String deviceId, XString serviceId, XString characteristicId, Uint8List? value, bool success);

//DUMMY Mention XString in docs, mention sanitization funcs
abstract class QuickBluePlatform extends PlatformInterface {
  QuickBluePlatform() : super(token: _token);

  static final Object _token = Object();

  static QuickBluePlatform _instance = Platform.isLinux ? QuickBlueLinux() : MethodChannelQuickBlue(); // Is there a reason this didn't already check platform?

  static QuickBluePlatform get instance => _instance;

  static set instance(QuickBluePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  void setLogger(QuickLogger logger);

  Future<bool> isBluetoothAvailable();

  Stream<int> get availabilityChangeStream;

  Future<void> startScan(List<String>? serviceUUIDs); //DUMMY Note that these are not XString

  Future<void> stopScan();

  Stream<dynamic> get scanResultStream;

  Future<void> connect(String deviceId);

  Future<void> disconnect(String deviceId);

  OnConnectionChanged? onConnectionChanged;

  Future<void> discoverServices(String deviceId);

  OnServiceDiscovered? onServiceDiscovered;

  Future<void> setNotifiable(String deviceId, XString service,
      XString characteristic, BleInputProperty bleInputProperty);

  OnValueChanged? onValueChanged;

  OnWroteCharacteristic? onWroteCharacteristic;

  Future<void> readValue(
      String deviceId, XString service, XString characteristic);

  Future<void> writeValue(
      String deviceId,
      XString service,
      XString characteristic,
      Uint8List value,
      BleOutputProperty bleOutputProperty);

  Future<int> requestMtu(String deviceId, int expectedMtu);
}
