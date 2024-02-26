import 'dart:async';
import 'dart:typed_data';

import 'package:bluez/bluez.dart';
import 'package:collection/collection.dart';
import 'package:convert/convert.dart';
import 'package:logging/logging.dart';

import 'quick_blue_platform_interface.dart';

//CHECK Something's weird on Linux.  I remember this DID WORK FINE about the very first time I tried it, but now (even when I roll back) it's being glitchy.
//  It seems like there's maybe something weird about 1. running things unawaited, 2. not leaving a delay between different calls, 3. scanning more than once (it never marks the cessation of scanning?)

class QuickBlueLinux extends QuickBluePlatform {
  // For example/.dart_tool/flutter_build/generated_main.dart
  static registerWith() {
    QuickBluePlatform.instance = QuickBlueLinux();
  }

  bool isInitialized = false;

  final BlueZClient _client = BlueZClient();

  BlueZAdapter? _activeAdapter;

  Future<void> _ensureInitialized() async {
    if (!isInitialized) {
      await _client.connect();

      _activeAdapter ??=
          _client.adapters.firstWhereOrNull((adapter) => adapter.powered);
      if (_activeAdapter == null) {
        if (_client.adapters.isEmpty) {
          throw Exception('Bluetooth adapter unavailable');
        }
        await _client.adapters.first.setPowered(true);
        _activeAdapter = _client.adapters.first;
      }
      _client.deviceAdded.listen(_onDeviceAdd);

      _activeAdapter?.propertiesChanged.listen((List<String> properties) {
        if (properties.contains('Powered')) {
          _availabilityStateController.add(availabilityState);
        }
      });
      _availabilityStateController.add(availabilityState);
      isInitialized = true;
    }
  }

  QuickLogger? _logger;

  @override
  void setLogger(QuickLogger logger) {
    _logger = logger;
  }

  void _log(String message, {Level logLevel = Level.INFO}) {
    _logger?.log(logLevel, message);
  }

  @override
  Future<bool> isBluetoothAvailable() async {
    await _ensureInitialized();
    _log('isBluetoothAvailable invoke success');
    return _activeAdapter!.powered;
  }

  // FIXME Close
  final StreamController<AvailabilityState> _availabilityStateController =
      StreamController.broadcast();

  @override
  Stream<int> get availabilityChangeStream =>
      _availabilityStateController.stream.map((state) => state.value);

  AvailabilityState get availabilityState {
    return _activeAdapter!.powered
        ? AvailabilityState.poweredOn
        : AvailabilityState.poweredOff;
  }

  @override
  Future<void> startScan(List<String>? serviceUUIDs) async { //DUMMY Note not XString
    await _ensureInitialized();
    _log('startScan invoke success');

    if (!_activeAdapter!.discovering) {
      _activeAdapter!.startDiscovery(); //TODO This is async.  Should it be awaited, or should it have error handlers attached?
      _client.devices.forEach(_onDeviceAdd);
    } else {
      _log('startScan not triggered because we are already scanning');
    }
  }

  @override
  Future<void> stopScan() async {
    await _ensureInitialized();
    _log('stopScan invoke success');

    if (!_activeAdapter!.discovering) {
      _activeAdapter!.stopDiscovery();
    }
  }

  // FIXME Close
  final StreamController<dynamic> _scanResultController = //DUMMY Ensure what's added
      StreamController.broadcast();

  @override
  Stream get scanResultStream => _scanResultController.stream;

  void _onDeviceAdd(BlueZDevice device) {
    _scanResultController.add({
      'deviceId': device.address,
      'name': device.alias,
      'manufacturerDataHead': device.manufacturerDataHead,
      'rssi': device.rssi,
    });
  }

  BlueZDevice _findDeviceById(String deviceId) {
    var device = _client.devices
        .firstWhereOrNull((device) => device.address == deviceId);
    if (device == null) {
      throw Exception('Unknown deviceId:$deviceId');
    }
    return device;
  }

  @override
  Future<void> connect(String deviceId) async {
    await _findDeviceById(deviceId).connect().then((_) {
      onConnectionChanged?.call(deviceId, BlueConnectionState.connected);
    });
  }

  @override
  Future<void> disconnect(String deviceId) async {
    await _findDeviceById(deviceId).disconnect().then((_) {
      onConnectionChanged?.call(deviceId, BlueConnectionState.disconnected);
    });
  }

  @override
  Future<void> discoverServices(String deviceId) async {
    var device = _findDeviceById(deviceId);

    Map<String, int> ss = {};
    for (var service in device.gattServices) {
      _log("Service ${service.uuid}");
      ss["${service.uuid}"] ??= -1;
      ss["${service.uuid}"] = ss["${service.uuid}"]! + 1;
      var sxi = ss["${service.uuid}"]!;
      var sxs = s2x("${service.uuid}", sxi);

      Map<String, int> cs = {};
      List<XString> characteristics = [];
      for (var characteristic in service.characteristics) {
        _log("    Characteristic ${characteristic.uuid}");
        cs["${characteristic.uuid}"] ??= -1;
        cs["${characteristic.uuid}"] = cs["${characteristic.uuid}"]! + 1;
        var cxi = cs["${characteristic.uuid}"]!;
        characteristics.add(s2x("${characteristic.uuid}", cxi));
      }

      onServiceDiscovered?.call(
          deviceId, sxs, characteristics);
    }
  }

  String x2ss(XString xs) {
    var i = xs.indexOf(":");
    if (i == -1) {
      return xs;
    } else {
      return xs.substring(0, i);
    }
  }

  int? x2si(XString xs) {
    var i = xs.indexOf(":");
    if (i == -1) {
      return 0; //DUMMY //CHECK Not sure about this one
    } else {
      return int.tryParse(xs.substring(i + 1));
    }
  }

  XString s2x(String s, [int i = 0]) {
    return "$s:$i";
  }

  XString ensureX(String s) { //DUMMY Capitalization, here and elsewhere?  I mean, I guess it wasn't doing it BEFORE....
    var i = s.indexOf(":");
    if (i == -1) {
      return "$s:0";
    }
    return s;
  }

  BlueZGattCharacteristic _getCharacteristic(
      String deviceId, XString service, XString characteristic) {
    var device = _findDeviceById(deviceId);
    service = ensureX(service);
    characteristic = ensureX(characteristic);

    // XString to object

    BlueZGattService? s = null;

    //THINK I do this in more than one place....
    // I'm assuming they're in a fixed order, which seems reasonable.
    {
      Map<String, int> ss = {};
      for (var x in device.gattServices) {
        ss["${x.uuid}"] ??= -1;
        ss["${x.uuid}"] = ss["${x.uuid}"]! + 1;
        var sxi = ss["${x.uuid}"]!;
        var sxs = s2x("${x.uuid}", sxi);

        if (service == sxs) {
          s = x;
          break;
        }
      }
    }

    BlueZGattCharacteristic? c = null;
    if (s != null) {
      //THINK I do this in more than one place....
      // I'm assuming they're in a fixed order, which seems reasonable.
      Map<String, int> cs = {};
      for (var x in s.characteristics) {
        cs["${x.uuid}"] ??= -1;
        cs["${x.uuid}"] = cs["${x.uuid}"]! + 1;
        var cxi = cs["${x.uuid}"]!;
        var cxs = s2x("${x.uuid}", cxi);

        if (characteristic == cxs) {
          c = x;
          break;
        }
      }
    }

    if (c == null) {
      throw Exception('Unknown characteristic:$characteristic');
    }
    return c;
  }

  // <"xservice*xchar", List<properties>>
  final Map<XString, StreamSubscription<List<String>>> //DUMMY ???
      _characteristicPropertiesSubscriptions = {};

  @override
  Future<void> setNotifiable(String deviceId, XString service,
      XString characteristic, BleInputProperty bleInputProperty) async {
    service = ensureX(service);
    characteristic = ensureX(characteristic);
    var c = _getCharacteristic(deviceId, service, characteristic);

    if (bleInputProperty != BleInputProperty.disabled) {
      c.startNotify(); //TODO This is async.  Should it be awaited, or should it have error handlers attached?
      void onPropertiesChanged(properties) {
        if (properties.contains('Value')) {
          _log(
              'onCharacteristicPropertiesChanged $characteristic, ${hex.encode(c.value)}');
          onValueChanged?.call(
              deviceId, service, characteristic, Uint8List.fromList(c.value));
        }
      }

      _characteristicPropertiesSubscriptions["$service*$characteristic"] ??=
          c.propertiesChanged.listen(onPropertiesChanged);
    } else {
      c.stopNotify(); //TODO This is async.  Should it be awaited, or should it have error handlers attached?
      _characteristicPropertiesSubscriptions.remove("$service*$characteristic")?.cancel(); //TODO This is async.  Should it be awaited, or should it have error handlers attached?
    }
  }

  @override
  Future<void> readValue(
      String deviceId, XString service, XString characteristic) async {
    service = ensureX(service);
    characteristic = ensureX(characteristic);
    var c = _getCharacteristic(deviceId, service, characteristic);

    var data = await c.readValue();
    _log('readValue $service $characteristic, ${hex.encode(data)}');
    onValueChanged?.call(deviceId, service, characteristic, Uint8List.fromList(data));
  }

  @override
  Future<void> writeValue(
      String deviceId,
      XString service,
      XString characteristic,
      Uint8List value,
      BleOutputProperty bleOutputProperty) async {
    service = ensureX(service);
    characteristic = ensureX(characteristic);
    var c = _getCharacteristic(deviceId, service, characteristic);

    try {
      if (bleOutputProperty == BleOutputProperty.withResponse) {
        await c.writeValue(value, type: BlueZGattCharacteristicWriteType.request);
      } else {
        await c.writeValue(value, type: BlueZGattCharacteristicWriteType.command);
      }
      //CHECK I'm not sure if writeValue waits for write confirmation before returning, so I don't know if this is right.  I also don't know if withoutResponse should trigger this or not.
      // Note: testing tentatively suggests that it does wait.
      onWroteCharacteristic?.call(deviceId, service, characteristic, value, true);
    } catch (e, s) {
      onWroteCharacteristic?.call(deviceId, service, characteristic, value, false);
      rethrow;
    }
    _log('writeValue $service $characteristic, ${hex.encode(value)}');
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) {
    // TODO: implement requestMtu
    throw UnimplementedError();
  }
}

extension BlueZDeviceExtension on BlueZDevice {
  Uint8List get manufacturerDataHead {
    if (manufacturerData.isEmpty) return Uint8List(0);

    final sorted = manufacturerData.entries.toList()
      ..sort((a, b) => a.key.id - b.key.id);
    return Uint8List.fromList(sorted.first.value);
  }
}
