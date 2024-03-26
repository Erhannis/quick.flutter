import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'package:quick_blue/quick_blue.dart';

import 'src/hash.dart';

const GSS_SUFFIX = "-0000-1000-8000-00805f9b34fb";

typedef XString = String;
typedef DeviceId = String;
//typedef SCString = String; //CHECK Eh...I'm not totally sure which direction to go.  Should probably at least add some more helper functions.
typedef SCString = Pair<XString, XString>;

/**
 * QuickBlue only provides a single "setConnectionHandler", for all devices.<br/>
 * So we can't have multiple listeners setting that.  Register your callback here.<br/>
 * <br/>
 * Don't set your own handlers on QuickBlue.  If it happens, call [resetHandlers].<br/>
 * <br/>
 * May not work right if you have multiple Isolates using QuickBlue.<br/>
 */
class BluetoothCallbackTracker { //TODO Make static instead of singleton?
  static late final INSTANCE = BluetoothCallbackTracker._();
  final WaitGroup _initialized = WaitGroup.of(1);

  final _scanSC = StreamController<BlueScanResult>();
  late final _scanStream = _scanSC.stream.asBroadcastStream();
  final Map<DeviceId, StreamController<Pair<XString, List<XString>>>> _serviceSCs = {};
  final Map<DeviceId, Stream<Pair<XString, List<XString>>>> _serviceStreams = {};
  final Map<DeviceId, StreamController<BlueConnectionState>> _connectionSCs = {};
  final Map<DeviceId, Stream<BlueConnectionState>> _connectionStreams = {};
  final Map<DeviceId, StreamController<Pair<SCString, Uint8List>>> _deviceValueSCs = {};
  final Map<DeviceId, Stream<Pair<SCString, Uint8List>>> _deviceValueStreams = {};
  final Map<Pair<DeviceId, SCString>, StreamController<Uint8List>> _charValueSCs = {};
  final Map<Pair<DeviceId, SCString>, Stream<Uint8List>> _charValueStreams = {};
  final Map<Pair<DeviceId, SCString>, StreamController<Pair<Uint8List?, bool>>> _wroteCharSCs = {};
  final Map<Pair<DeviceId, SCString>, Stream<Pair<Uint8List?, bool>>> _wroteCharStreams = {};

  // Some platforms demand uppercase, some demand lowercase.  Facepalm.
  static DeviceId _normalizeDevice(String s) {
    //CHECK These should probably be double-checked
    if (Platform.isWindows) {
      return s.toLowerCase();
    } else {
      return s.toUpperCase();
    }
  }

  static XString _normalizeService(XString s) {
    //CHECK These should probably be double-checked
    var i = s.indexOf(":");
    if (i == -1) {
      s = "$s:0";
    }
    i = s.indexOf(":");
    if (s.length == 6) {
      var prefix = s.substring(0, i);
      var suffix = s.substring(i+1);
      s = "0000$prefix$GSS_SUFFIX:$suffix";
    }
    // By here it should be a normalized XString.  Now for case:
    if (Platform.isWindows || Platform.isMacOS || Platform.isIOS || Platform.isLinux) {
      return s.toLowerCase();
    } else { // Android
      return s.toUpperCase();
    }
  }

  void _ensureServiceScan(DeviceId deviceId) {
    deviceId = _normalizeDevice(deviceId);
    if (!_serviceSCs.containsKey(deviceId)) {
      final sc = StreamController<Pair<XString, List<XString>>>();
      _serviceSCs[deviceId] = sc;
      final s = sc.stream.asBroadcastStream();
      s.listen((m) {});
      _serviceStreams[deviceId] = s;
    }
  }

  void _ensureConnection(DeviceId deviceId) {
    deviceId = _normalizeDevice(deviceId);
    if (!_connectionSCs.containsKey(deviceId)) {
      final sc = StreamController<BlueConnectionState>();
      _connectionSCs[deviceId] = sc;
      final s = sc.stream.asBroadcastStream();
      s.listen((m) {});
      _connectionStreams[deviceId] = s;
    }
  }

  void _ensureDeviceValue(DeviceId deviceId) {
    deviceId = _normalizeDevice(deviceId);
    if (!_deviceValueSCs.containsKey(deviceId)) {
      final sc = StreamController<Pair<SCString, Uint8List>>();
      _deviceValueSCs[deviceId] = sc;
      final s = sc.stream.asBroadcastStream();
      s.listen((m) {});
      _deviceValueStreams[deviceId] = s;
    }
  }

  void _ensureCharValue(DeviceId deviceId, XString serviceId, XString characteristicId) {
    deviceId = _normalizeDevice(deviceId);
    serviceId = _normalizeService(serviceId);
    characteristicId = _normalizeService(characteristicId);
    final p = Pair(deviceId, Pair(serviceId, characteristicId));
    if (!_charValueSCs.containsKey(p)) {
      final sc = StreamController<Uint8List>();
      _charValueSCs[p] = sc;
      final s = sc.stream.asBroadcastStream();
      s.listen((m) {});
      _charValueStreams[p] = s;
    }
  }

  void _ensureWroteChar(DeviceId deviceId, XString serviceId, XString characteristicId) {
    deviceId = _normalizeDevice(deviceId);
    serviceId = _normalizeService(serviceId);
    characteristicId = _normalizeService(characteristicId);
    final p = Pair(deviceId, Pair(serviceId, characteristicId));
    if (!_wroteCharSCs.containsKey(p)) {
      final sc = StreamController<Pair<Uint8List?, bool>>();
      _wroteCharSCs[p] = sc;
      final s = sc.stream.asBroadcastStream();
      s.listen((m) {});
      _wroteCharStreams[p] = s;
    }
  }

  Stream<BlueScanResult> subscribeForScanResults() {
    return _scanStream;
  }

  Stream<Pair<XString, List<XString>>> subscribeForServiceResults(String deviceId) {
    deviceId = _normalizeDevice(deviceId);
    _ensureServiceScan(deviceId);
    return _serviceStreams[deviceId]!;
  }

  Stream<BlueConnectionState> subscribeForConnectionResults(String deviceId) {
    deviceId = _normalizeDevice(deviceId);
    _ensureConnection(deviceId);
    return _connectionStreams[deviceId]!;
  }

  /**
   * Subscribe to any (serviceId, characteristicId, data) coming in for a given deviceId.<br/>
   */
  Stream<Pair<SCString, Uint8List>> subscribeForDeviceValues(String deviceId) {
    deviceId = _normalizeDevice(deviceId);
    // log("Adding subscription for $deviceId");
    _ensureDeviceValue(deviceId);
    return _deviceValueStreams[deviceId]!;
  }

  /**
   * Subscribe to any data coming in for a given deviceId and characteristicId.<br/>
   */ //DUMMY Should probably support same chars on different services
  Stream<Uint8List> subscribeForCharacteristicValues(String deviceId, XString serviceId, XString characteristicId) {
    deviceId = _normalizeDevice(deviceId);
    serviceId = _normalizeService(serviceId);
    characteristicId = _normalizeService(characteristicId);
    _ensureCharValue(deviceId, serviceId, characteristicId);
    return _charValueStreams[Pair(deviceId, Pair(serviceId, characteristicId))]!;
  }

  /**
   * Subscribe to notifications of success of outgoing writes to characteristics.<br/>
   * Stream is of characteristic `value` (exactly what that means may depend on platform, not sure) and `success`.<br/>
   */
  Stream<Pair<Uint8List?, bool>> subscribeForWroteCharacteristic(String deviceId, XString serviceId, XString characteristicId) {
    deviceId = _normalizeDevice(deviceId);
    serviceId = _normalizeService(serviceId);
    characteristicId = _normalizeService(characteristicId);
    _ensureWroteChar(deviceId, serviceId, characteristicId);
    return _wroteCharStreams[Pair(deviceId, Pair(serviceId, characteristicId))]!;
  }

  Set<Token> _scanTokens = {};
  Future<Token> startScan() async { //THINK Maybe return a Scan object with .stop()?
    await _initialized.wait();
    if (_scanTokens.isEmpty) {
      await QuickBlue.startScan();
    }
    var t = Token();
    _scanTokens.add(t);
    return t;
  }
  Future<void> stopScan(Token t) async {
    await _initialized.wait();
    _scanTokens.remove(t);
    if (_scanTokens.isEmpty) {
      await QuickBlue.stopScan();
    }
  }
  bool isScanning() {
    return _scanTokens.isNotEmpty;
  }

  Future<bool> isBluetoothAvailable() async {
    await _initialized.wait();
    return await QuickBlue.isBluetoothAvailable();
  }

  //DUMMY Many of these things will, occasionally, deadlock.  Deal with it somehow.
  //TODO These should be merged with the "subscribe" functions, frankly; they're here because of the way this grew into existence
  Future<void> connect(String deviceId) async {
    deviceId = _normalizeDevice(deviceId);
    await _initialized.wait();
    return QuickBlue.connect(deviceId);
  }
  Future<void> discoverServices(String deviceId) async {
    deviceId = _normalizeDevice(deviceId);
    await _initialized.wait();
    return QuickBlue.discoverServices(deviceId);
  }
  /// Warning!  I've noticed on Android that if I don't wait like 5 seconds between setNotifiable calls, the system seems to drop the ones after the first.
  Future<void> setNotifiable(String deviceId, XString service, XString characteristic, BleInputProperty bleInputProperty) async {
    await _initialized.wait();
    deviceId = _normalizeDevice(deviceId);
    service = _normalizeService(service);
    characteristic = _normalizeService(characteristic);
    return await QuickBlue.setNotifiable(deviceId, service, characteristic, bleInputProperty);
    // return Future.delayed(Duration(milliseconds: 5000));
  }
  Future<void> disconnect(String deviceId) async {
    await _initialized.wait();
    deviceId = _normalizeDevice(deviceId);
    return QuickBlue.disconnect(deviceId);
  }

  /**
   * Note that this just subscribes for one value, then requests a value.
   * It's possible it will return a value not triggered by the read - but that shouldn't matter for normal cases.
   * Note also that anything subscribed to the characteristic will get the value, too.
   */
  Future<Uint8List> readValue(String deviceId, String service, String characteristic) async { //CHECK This deadlocks sometimes.  Timeout all occurrences?
    await _initialized.wait();
    deviceId = _normalizeDevice(deviceId);
    service = _normalizeService(service);
    characteristic = _normalizeService(characteristic);
    Future<Uint8List> fVal = subscribeForCharacteristicValues(deviceId, service, characteristic).first;
    await QuickBlue.readValue(deviceId, service, characteristic);
    return await fVal;
  }
  Future<void> writeValue(String deviceId, XString service, XString characteristic, Uint8List data, {bool withoutResponse = false}) async {
    await _initialized.wait();
    deviceId = _normalizeDevice(deviceId);
    service = _normalizeService(service);
    characteristic = _normalizeService(characteristic);
    //CHECK This is failing on Android, and I don't know why.  "Characteristic unavailable".
    return QuickBlue.writeValue(deviceId, service, characteristic, data, withoutResponse ? BleOutputProperty.withoutResponse : BleOutputProperty.withResponse); // On Mac, this doesn't work withoutResponse ... Ok, it's no longer working WITH it.  :|
  }


  BluetoothCallbackTracker._() {
    // log("--> BluetoothCallbackTracker init");
    _scanStream.listen((x) {});

    unawaited(Future(() async {
      QuickBlue.scanResultStream.listen(_handleScanResult);
      _initialized.done();
    }));

    resetHandlers();
    // log("<-- BluetoothCallbackTracker init");
  }

  void resetHandlers() {
    QuickBlue.setServiceHandler(_handleServiceDiscovery);
    QuickBlue.setConnectionHandler(_handleConnectionChange);
    QuickBlue.setValueHandler(_handleValueChange);
    QuickBlue.setOnWroteCharateristicHandler(_handleWroteChar);
  }

  void _handleScanResult(BlueScanResult result) {
    result.deviceId = _normalizeDevice(result.deviceId); // This is DUMB
    // log('onScanResult ${result.rssi} ${result.deviceId} ${result.name}');
    _scanSC.add(result);
  }

  void _handleServiceDiscovery(String deviceId, XString serviceId, List<XString> characteristicIds) {
    deviceId = _normalizeDevice(deviceId);
    serviceId = _normalizeService(serviceId);
    for (int i = 0; i < characteristicIds.length; i++) {
      characteristicIds[i] = _normalizeService(characteristicIds[i]);
    }
    // log('_handleServiceDiscovery $deviceId, $serviceId, $characteristicIds');
    _ensureServiceScan(deviceId);
    _serviceSCs[deviceId]!.add(Pair(serviceId, characteristicIds));
  }

  void _handleConnectionChange(String deviceId, BlueConnectionState state) {
    deviceId = _normalizeDevice(deviceId);
    _ensureConnection(deviceId);
    _connectionSCs[deviceId]!.add(state);
  }

  void _handleValueChange(DeviceId deviceId, XString serviceId, XString characteristicId, Uint8List value) {
    deviceId = _normalizeDevice(deviceId);
    serviceId = _normalizeService(serviceId);
    characteristicId = _normalizeService(characteristicId);
    log('_handleValueChange $deviceId, $serviceId, $characteristicId, ${value}');
    _ensureCharValue(deviceId, serviceId, characteristicId);
    _charValueSCs[Pair(deviceId, Pair(serviceId, characteristicId))]!.add(value);
    _ensureDeviceValue(deviceId);
    _deviceValueSCs[deviceId]!.add(Pair(Pair(serviceId, characteristicId), value));
  }

  void _handleWroteChar(DeviceId deviceId, XString serviceId, XString characteristicId, Uint8List? value, bool success) {
    log("_handleWroteChar $deviceId $serviceId $characteristicId $success");
    // log("_handleWroteChar $deviceId $characteristicId $success");
    deviceId = _normalizeDevice(deviceId);
    serviceId = _normalizeService(serviceId);
    characteristicId = _normalizeService(characteristicId);
    // log('_handleWroteChar $deviceId, $characteristicId, ${value}, $success');
    _ensureWroteChar(deviceId, serviceId, characteristicId);
    _wroteCharSCs[Pair(deviceId, Pair(serviceId, characteristicId))]!.add(Pair(value, success));
  }
}

class Pair<A, B> {
  final A a;
  final B b;

  const Pair(this.a, this.b);

  @override
  bool operator ==(Object other) {
    if (!(other is Pair<A, B>)) {
      return false;
    }
    return (a == other.a && b == other.b);
  }

  @override
  int get hashCode => hash2(a, b);

  @override
  String toString() {
    return "($a,$b)";
  }
}

class Triple<A, B, C> {
  final A a;
  final B b;
  final C c;

  const Triple(this.a, this.b, this.c);

  @override
  bool operator ==(Object other) {
    if (!(other is Triple<A, B, C>)) {
      return false;
    }
    return (a == other.a && b == other.b && c == other.c);
  }

  @override
  int get hashCode => hash3(a, b, c);

  @override
  String toString() {
    return "($a,$b,$c)";
  }
}

class Token {
}

class WaitGroup {
  var _c = Completer<void>();
  var _i = 0;

  WaitGroup();

  WaitGroup.of(int count): _i = count;

  void add(int j) {
    _i += j;
  }

  void done() {
    _i--;
    if (_i == 0) {
      _c.complete(null);
      _c = Completer<void>();
    }
  }

  Future<void> wait() async {
    if (_i > 0) {
      return _c.future;
    }
  }
}

bool _isX(String a) {
  return a.contains(":");
}

String _x2ss(XString xs) {
  var i = xs.indexOf(":");
  if (i == -1) {
    return xs;
  } else {
    return xs.substring(0, i);
  }
}

/**
 * Comparing UUIDs is sorta complicated.
 * Comparison is case-insensitive.
 * Since different characteristics can have the same UUID, the XString format was added, which complicates comparisons.<br/>
 * <br/>
 * abcd is a abcd.<br/>
 * abcd:0 is a abcd.<br/>
 * abcd:0 is a abcd:0.<br/>
 * abcd:0 is not a abcd:1.<br/>
 * abcd is not a abcd:0.<br/>
 * abcd is not wxyz, with or without suffixes.<br/>
 */
bool uuidAisaB(String a, String b) {
  if (_isX(a)) {
    if (_isX(b)) {
      // a:i, b:j
      return uuidsEqual(a, b);
    } else {
      // a:i, b
      return uuidsEqual(_x2ss(a), b);
    }
  } else {
    if (_isX(b)) {
      // a, b:j
      return false;
    } else {
      // a, b
      return uuidsEqual(a, b);
    }
  }
}

bool uuidsEqual(String? a, String? b) { //DUMMY Check this
  if (a == b) {
    return true;
  }
  if (a == null || b == null) {
    return false;
  }
  return BluetoothCallbackTracker._normalizeService(a) == BluetoothCallbackTracker._normalizeService(b);
}



Future<bool> requestBluetooth() async {
  if (!Platform.isLinux) {
    if (!(Platform.isMacOS || Platform.isIOS)) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.location,
      ].request();
      if (statuses.values.any((v) => !v.isGranted)) {
        log("permission(s) denied");
        return false;
      }
      statuses = await [
        Permission.locationAlways,
      ].request();
      if (statuses.values.any((v) => !v.isGranted)) {
        log("locationAlways permission denied");
        return false;
      }
    } else {
      // I think the WinBle check is bugged, so we're only checking on Mac
      var s = await BluetoothCallbackTracker.INSTANCE.isBluetoothAvailable();
      log("BLE available 1: $s");
      // Logger.root.info('BLE available 1: $s');
      if (!s) {
        await Future.delayed(Duration(milliseconds: 1000)); // Mac: for some reason this works
        s = await BluetoothCallbackTracker.INSTANCE.isBluetoothAvailable();
        log("BLE available 2: $s");
        // Logger.root.info('BLE available 2: $s');
      }
    }
  }
  var sub = BluetoothCallbackTracker.INSTANCE.subscribeForScanResults().listen((event) {
    log("initscan: ${event.deviceId} ${event.name} ${event.rssi}");
  },);
  unawaited(BluetoothCallbackTracker.INSTANCE.startScan().then((t) async { // Some platforms don't let you connect to a device unless you've scanned it first.  Eyeroll.
    await Future.delayed(Duration(seconds: 30)); //TODO Parameterize?
    await BluetoothCallbackTracker.INSTANCE.stopScan(t); //TODO Also stop scanning on widget finalize?
    await sub.cancel();
  }));
  return true;
}