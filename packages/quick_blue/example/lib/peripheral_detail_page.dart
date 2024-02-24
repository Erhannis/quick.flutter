// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:quick_blue/quick_blue.dart';

String gssUuid(String code) => '0000$code-0000-1000-8000-00805f9b34fb';

final GSS_SERV__BATTERY = gssUuid('180f');
final GSS_CHAR__BATTERY_LEVEL = gssUuid('2a19');

const WOODEMI_SUFFIX = 'ba5e-f4ee-5ca1-eb1e5e4b1ce0';

const WOODEMI_SERV__COMMAND = '57444d01-$WOODEMI_SUFFIX';
const WOODEMI_CHAR__COMMAND_REQUEST = '57444e02-$WOODEMI_SUFFIX';
const WOODEMI_CHAR__COMMAND_RESPONSE = WOODEMI_CHAR__COMMAND_REQUEST;

const WOODEMI_MTU_WUART = 247;

class PeripheralDetailPage extends StatefulWidget {
  const PeripheralDetailPage({
    Key? key,
    required this.deviceId,
  }) : super(key: key);

  final String deviceId;

  @override
  State<StatefulWidget> createState() {
    return _PeripheralDetailPageState();
  }
}

class _PeripheralDetailPageState extends State<PeripheralDetailPage> {
  @override
  void initState() {
    super.initState();
    QuickBlue.setConnectionHandler(_handleConnectionChange);
    QuickBlue.setServiceHandler(_handleServiceDiscovery);
    QuickBlue.setValueHandler(_handleValueChange);
    QuickBlue.setOnWroteCharateristicHandler(_handleOnWroteCharacteristic);
  }

  @override
  void dispose() {
    super.dispose();
    QuickBlue.setOnWroteCharateristicHandler(null);
    QuickBlue.setValueHandler(null);
    QuickBlue.setServiceHandler(null);
    QuickBlue.setConnectionHandler(null);
  }

  void _handleConnectionChange(String deviceId, BlueConnectionState state) {
    debugPrint('_handleConnectionChange $deviceId, $state');
  }

  void _handleServiceDiscovery(String deviceId, String serviceId, List<String> characteristicIds) {
    debugPrint('_handleServiceDiscovery $deviceId, $serviceId, $characteristicIds');
  }

  void _handleValueChange(String deviceId, String serviceId, String characteristicId, Uint8List value) {
    debugPrint('_handleValueChange $deviceId, $serviceId, $characteristicId, ${hex.encode(value)}');
  }

  void _handleOnWroteCharacteristic(String deviceId, String serviceId, String characteristicId, Uint8List? value, bool success) {
    debugPrint('_handleOnWroteCharacteristic $deviceId, $serviceId, $characteristicId, ${value == null ? null : hex.encode(value)}, $success');
  }

  final serviceUUID = TextEditingController(text: WOODEMI_SERV__COMMAND);
  final characteristicUUID =
      TextEditingController(text: WOODEMI_CHAR__COMMAND_REQUEST);
  final binaryCode = TextEditingController(
      text: hex.encode([0x01, 0x0A, 0x00, 0x00, 0x00, 0x01]));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PeripheralDetailPage'),
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              ElevatedButton(
                child: const Text('connect'),
                onPressed: () {
                  QuickBlue.connect(widget.deviceId);
                },
              ),
              ElevatedButton(
                child: const Text('disconnect'),
                onPressed: () {
                  QuickBlue.disconnect(widget.deviceId);
                },
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              ElevatedButton(
                child: const Text('discoverServices'),
                onPressed: () {
                  QuickBlue.discoverServices(widget.deviceId);
                },
              ),
            ],
          ),
          ElevatedButton(
            child: const Text('setNotifiable'),
            onPressed: () {
              QuickBlue.setNotifiable(
                  widget.deviceId, WOODEMI_SERV__COMMAND, WOODEMI_CHAR__COMMAND_RESPONSE,
                  BleInputProperty.indication);
            },
          ),
          TextField(
            controller: serviceUUID,
            decoration: const InputDecoration(
              labelText: 'ServiceUUID',
            ),
          ),
          TextField(
            controller: characteristicUUID,
            decoration: const InputDecoration(
              labelText: 'CharacteristicUUID',
            ),
          ),
          TextField(
            controller: binaryCode,
            decoration: const InputDecoration(
              labelText: 'Binary code',
            ),
          ),
          ElevatedButton(
            child: const Text('send'),
            onPressed: () {
              var value = Uint8List.fromList(hex.decode(binaryCode.text));
              QuickBlue.writeValue(
                  widget.deviceId, serviceUUID.text, characteristicUUID.text,
                  value, BleOutputProperty.withResponse);
            },
          ),
          ElevatedButton(
            child: const Text('readValue battery'),
            onPressed: () async {
              await QuickBlue.readValue(
                  widget.deviceId,
                  GSS_SERV__BATTERY,
                  GSS_CHAR__BATTERY_LEVEL);
            },
          ),
          ElevatedButton(
            child: const Text('requestMtu'),
            onPressed: () async {
              var mtu = await QuickBlue.requestMtu(widget.deviceId, WOODEMI_MTU_WUART);
              debugPrint('requestMtu $mtu');
            },
          ),
        ],
      ),
    );
  }
}