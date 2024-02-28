# quick_blue

A cross-platform (Android/iOS/macOS/Windows/Linux) BluetoothLE plugin for Flutter

# Usage

- [Receive BLE availability changes](#receive-ble-availability-changes)
- [Scan BLE peripheral](#scan-ble-peripheral)
- [Connect BLE peripheral](#connect-ble-peripheral)
- [Discover services of BLE peripheral](#discover-services-of-ble-peripheral)
- [Transfer data between BLE central & peripheral](#transfer-data-between-ble-central--peripheral)

| API | Android | iOS | macOS | Windows | Linux |
| :--- | :---: | :---: | :---: | :---: | :---: |
| availabilityChangeStream | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| isBluetoothAvailable | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| startScan/stopScan | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| connect/disconnect | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| discoverServices | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| setNotifiable | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| readValue | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| writeValue | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| requestMtu | ✔️ | ✔️ | ✔️ | ✔️ |  |

> * Windows' APIs are little different on `discoverServices`: https://github.com/woodemi/quick_blue/issues/76

Heads up!  Two things to be aware of.
1. The system now distinguishes between multiple characteristics with identical UUIDs, because apparently that's a thing the BLE spec permits for some reason.  It does this by appending e.g. ":0" to the first instance of a UUID in a given grouping (services, or characteristics of a given service).  Subsequent instances get ":1", ":2", etc.  If you pass the library a plain uuid, :0 is assumed.  See uuidAisaB, and uuidsEqual.  (To help note places a suffix is permitted/expected, I've added a type alias "XString".)
2. QuickBlue itself lumps callbacks etc. together, which makes it hard to use for more than one thing at a time, so I've added BluetoothCallbackTracker.  It is recommended over raw QuickBlue, for its convenience.  For example:

```dart
  // In main(), before runApp(const MyApp()), you could put
  WidgetsFlutterBinding.ensureInitialized();
  await requestBluetooth();

  // ...but in general it's gently recommended you request bluetooth shortly before doing bluetooth stuff:
  await requestBluetooth(); // Note this triggers a scan

  var DEVICE = "device id, or get via scan";
  var SERVICE = "service id, or get via scan";
  var CHARACTERISTIC = "characteristic id, or get via scan";
  
  // For later canceling them, on e.g. disconnect
  List<StreamSubscription> streams = [];
  
  streams.add(BluetoothCallbackTracker.INSTANCE.subscribeForScanResults().listen((event) {
    log("scan: ${event.deviceId} ${event.name} ${event.rssi}");
  },));
  var t = await BluetoothCallbackTracker.INSTANCE.startScan();
  await Future.delayed(Duration(milliseconds: 30000));
  await BluetoothCallbackTracker.INSTANCE.stopScan(t);

  streams.add(BluetoothCallbackTracker.INSTANCE.subscribeForConnectionResults(DEVICE).listen((event) async {
    log("connect? $event");
    if (event == BlueConnectionState.connected) {
      streams.add(BluetoothCallbackTracker.INSTANCE.subscribeForServiceResults(DEVICE).listen((event) async {
        log("service results: $event");
        // for (var c in event.b) {
        //   // Read all characteristics
        //   unawaited(BluetoothCallbackTracker.INSTANCE.readValue(DEVICE, event.a, c).then((event) {
        //     log("read $c : $event / ${String.fromCharCodes(event)}");
        //   }));
        // }
      }));
      log("discover services");
      await BluetoothCallbackTracker.INSTANCE.discoverServices(DEVICE);

      await Future.delayed(Duration(milliseconds: 5000));

      // This could instead go in the services callback, in some form
      streams.add(BluetoothCallbackTracker.INSTANCE.subscribeForCharacteristicValues(DEVICE, SERVICE, CHARACTERISTIC).listen((event) {
        log("$CHARACTERISTIC got value $event");
      }));
      try {
        // Warning!  I've noticed on Android that if I don't wait like 5 seconds between setNotifiable calls, the system seems to drop the ones after the first.
        log("Setting notifiable $SERVICE $CHARACTERISTIC");
        await BluetoothCallbackTracker.INSTANCE.setNotifiable(DEVICE, SERVICE, CHARACTERISTIC, BleInputProperty.notification);
      } catch (e, s) {
        log("error setting notifiable $e $s");
      }

      // This could instead go in the services callback, in some form
      streams.add(BluetoothCallbackTracker.INSTANCE.subscribeForCharacteristicValues(DEVICE, SERVICE, CHARACTERISTIC2).listen((event) {
        log("$CHARACTERISTIC2 got value $event");
      }));
      try {
        // Warning!  I've noticed on Android that if I don't wait like 5 seconds between setNotifiable calls, the system seems to drop the ones after the first.
        log("Setting notifiable $SERVICE $CHARACTERISTIC2");
        await BluetoothCallbackTracker.INSTANCE.setNotifiable(DEVICE, SERVICE, CHARACTERISTIC2, BleInputProperty.notification);
      } catch (e, s) {
        log("error setting notifiable $e $s");
      }

      await Future.delayed(Duration(milliseconds: 60000));

      await BluetoothCallbackTracker.INSTANCE.disconnect(DEVICE);
      for (var s in streams) {
        try {
          await s.cancel();
        } catch (e, s) {
          // Nothing
        }
      }
    }
  }));
  await BluetoothCallbackTracker.INSTANCE.connect(DEVICE);
```

## Receive BLE availability changes

iOS/macOS
```dart
QuickBlue.availabilityChangeStream.listen((state) {
  debugPrint('Bluetooth state: ${state.toString()}');
});
```


## Scan BLE peripheral

Android/iOS/macOS/Windows/Linux

```dart
QuickBlue.scanResultStream.listen((result) {
  print('onScanResult $result');
});

QuickBlue.startScan();
// ...
QuickBlue.stopScan();
```

## Connect BLE peripheral

Connect to `deviceId`, received from `QuickBlue.scanResultStream`

```dart
QuickBlue.setConnectionHandler(_handleConnectionChange);

void _handleConnectionChange(String deviceId, BlueConnectionState state) {
  print('_handleConnectionChange $deviceId, $state');
}

QuickBlue.connect(deviceId);
// ...
QuickBlue.disconnect(deviceId);
```

## Discover services of BLE peripheral

Discover services od `deviceId`

```dart
QuickBlue.setServiceHandler(_handleServiceDiscovery);

void _handleServiceDiscovery(String deviceId, String serviceId) {
  print('_handleServiceDiscovery $deviceId, $serviceId');
}

QuickBlue.discoverServices(deviceId);
```

## Transfer data between BLE central & peripheral

- Pull data from peripheral of `deviceId`

> Data would receive within value handler of `QuickBlue.setValueHandler`
> Because it is how [peripheral(_:didUpdateValueFor:error:)](https://developer.apple.com/documentation/corebluetooth/cbperipheraldelegate/1518708-peripheral) work on iOS/macOS

```dart
// Data would receive from value handler of `QuickBlue.setValueHandler`
QuickBlue.readValue(deviceId, serviceId, characteristicId);
```

- Send data to peripheral of `deviceId`

```dart
QuickBlue.writeValue(deviceId, serviceId, characteristicId, value);
```

- Receive data from peripheral of `deviceId`

```dart
QuickBlue.setValueHandler(_handleValueChange);

void _handleValueChange(String deviceId, String characteristicId, Uint8List value) {
  print('_handleValueChange $deviceId, $characteristicId, ${hex.encode(value)}');
}

QuickBlue.setNotifiable(deviceId, serviceId, characteristicId, true);
```