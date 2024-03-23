import CoreBluetooth

#if os(iOS)
import Flutter
import UIKit
#elseif os(OSX)
import Cocoa
import FlutterMacOS
#endif

public typealias XString = String

let GATT_HEADER_LENGTH = 3

let GSS_SUFFIX = "0000-1000-8000-00805f9b34fb"

// 4 funcs translated with ChatGPT
func x2ss(xs: XString) -> String { //DUMMY ensureX(xs) ?
    let i = xs.firstIndex(of: ":")
    if i == nil {
        return xs.lowercased()
    } else {
        if let range = i {
            return String(xs[..<range]).lowercased()
        }
        return xs.lowercased() // Fallback, should not happen due to the if check above
    }
}

func x2si(xs: XString) -> Int? { //DUMMY ensureX(xs) ?
    let i = xs.firstIndex(of: ":")
    if i == nil {
        return 0 //DUMMY //CHECK Not sure about this one
    } else {
        if let range = i {
            let startIndex = xs.index(after: range)
            let substring = String(xs[startIndex...])
            return Int(substring)
        }
        return nil // Should not happen, added for safety
    }
}

func s2x(_ s: String, _ i: Int = 0) -> XString {
    let s = s.lowercased() //DUMMY Hmmmmmm, I'm not sure about this, could conflict with native uuids
    return ensureX("\(s):\(i)") // ensureX for the short-checking
}

func ensureX(_ s: String) -> XString {
    var s = s.lowercased() //DUMMY Hmmmmmm, I'm not sure about this, could conflict with native uuids
    let i = s.firstIndex(of: ":")
    if let i {
        // There's a :
        // Split and check/fix short uuid
        let suffix = String(s[i...])
        s = String(s[..<i])
        if s.count < 10 { // Ditto
            s = "0000\(s)-\(GSS_SUFFIX)"
        }
        s = "\(s)\(suffix)"
    } else {
        // No :
        // Check/fix short uuid
        if s.count < 10 { // Too lazy to check the actual number
            s = "0000\(s)-\(GSS_SUFFIX)"
        }
        s = "\(s):0"
    }
    return s
}

extension CBUUID {
    public var uuidStr: String {
        get {
            uuidString.lowercased()
        }
    }
}

extension CBPeripheral {
    // FIXME https://forums.developer.apple.com/thread/84375
    public var uuid: UUID {
        get {
            value(forKey: "identifier") as! NSUUID as UUID
        }
    }

    public func getCharacteristic(_ characteristic: XString, of service: XString) -> CBCharacteristic? {
        let characteristic = ensureX(characteristic)
        let service = ensureX(service)
        var servicesMap: [String: Int] = [:]
        
        guard let services = self.services else { return nil }
        
        for s in services {
            let k = "\(s.uuid.uuidString)"
            servicesMap[k, default: -1] += 1
            let sxi = servicesMap[k]!
            let sxs = s2x(k, sxi)
            
            if sxs == service {
                // print("x2serv yes \(sxs) \(service)")
                var characteristicsMap: [String: Int] = [:]
                guard let characteristics = s.characteristics else { continue }
                
                for c in characteristics {
                    let ck = "\(c.uuid.uuidString)"
                    characteristicsMap[ck, default: -1] += 1
                    let cxi = characteristicsMap[ck]!
                    let cxs = s2x(ck, cxi)
                    
                    if cxs == characteristic {
                        // print("x2char yes \(cxs) \(characteristic)")
                        return c
                    }
                    // print("x2char no \(cxs) \(characteristic)")
                }
            } else {
                // print("x2serv no \(sxs) \(service)")
            }
        }
        return nil
    }

    func service2x(service: CBService) -> XString? {
        var ss: [String: Int] = [:]
        guard let services = self.services else { return nil }
        
        for x in services {
            let k = "\(x.uuid.uuidString)"
            ss[k, default: -1] += 1
            let sxi = ss[k]!
            let sxs = s2x(k, sxi)
            
            if x === service { //DUMMY Not sure this is right
                return sxs
            }
        }
        return nil
    }
    
    func characteristic2x(characteristic: CBCharacteristic) -> XString? {
        guard let characteristics = characteristic.service?.characteristics else { return nil }
        var cs: [String: Int] = [:]
        
        for x in characteristics {
            let k = "\(x.uuid.uuidString)"
            cs[k, default: -1] += 1
            let cxi = cs[k]!
            let cxs = s2x(k, cxi)
            
            if x === characteristic { //DUMMY Not sure this is right
                return cxs
            }
        }
        return nil
    }

    //THINK ...I don't think this is used?
    public func setNotifiable(_ bleInputProperty: String, for characteristic: XString, of service: XString) {
        let c = ensureX(characteristic)
        let s = ensureX(service)

        guard let characteristic = getCharacteristic(c, of: s) else {
            // print("setNotifiable yes \(bleInputProperty != "disabled") \(s) \(c)")
            return
        }
        // print("setNotifiable yes \(bleInputProperty != "disabled") \(s) \(c)")
        setNotifyValue(bleInputProperty != "disabled", for: characteristic)
    }
}

public class QuickBlueDarwin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
#if os(iOS)
        let messenger = registrar.messenger()
#elseif os(OSX)
        let messenger = registrar.messenger
#endif
        let method = FlutterMethodChannel(name: "quick_blue/method", binaryMessenger: messenger)
        let eventAvailabilityChange = FlutterEventChannel(name: "quick_blue/event.availabilityChange", binaryMessenger: messenger)
        let eventScanResult = FlutterEventChannel(name: "quick_blue/event.scanResult", binaryMessenger: messenger)
        let messageConnector = FlutterBasicMessageChannel(name: "quick_blue/message.connector", binaryMessenger: messenger)

        let instance = QuickBlueDarwin()
        registrar.addMethodCallDelegate(instance, channel: method)
        eventAvailabilityChange.setStreamHandler(instance)
        eventScanResult.setStreamHandler(instance)
        instance.messageConnector = messageConnector
    }

    private lazy var manager: CBCentralManager = { CBCentralManager(delegate: self, queue: nil) }()
    private var discoveredPeripherals = Dictionary<String, CBPeripheral>()

    private var availabilityChangeSink: FlutterEventSink?
    private var scanResultSink: FlutterEventSink?
    private var messageConnector: FlutterBasicMessageChannel!

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isBluetoothAvailable":
            result(manager.state == .poweredOn)
        case "startScan":
            let arguments = call.arguments as! Dictionary<String, Any>
            let serviceUUIDs = arguments["serviceUUIDs"] as? [String] //DUMMY String not XString
            if serviceUUIDs != nil && serviceUUIDs!.count > 0 {
                let serviceCBUUID = serviceUUIDs!.map({ uuid in
                    CBUUID(string: uuid)
                })
                manager.scanForPeripherals(withServices: serviceCBUUID)
            } else {
                manager.scanForPeripherals(withServices: nil)
            }
            result(nil)
        case "stopScan":
            manager.stopScan()
            
//            testbm = BLEManager()
//            dispatch {
//                Thread.sleep(forTimeInterval: Double(1000) / 1000.0)
//                testbm!.startScanning()
//            }
            
            result(nil)
        case "connect":
            let arguments = call.arguments as! Dictionary<String, Any>
            let deviceId = arguments["deviceId"] as! String
            guard let peripheral = discoveredPeripherals[deviceId] else {
                result(FlutterError(code: "IllegalArgument", message: "Unknown deviceId:\(deviceId)", details: nil))
                return
            }
            peripheral.delegate = self
            manager.connect(peripheral)
            result(nil)
        case "disconnect":
            let arguments = call.arguments as! Dictionary<String, Any>
            let deviceId = arguments["deviceId"] as! String
            guard let peripheral = discoveredPeripherals[deviceId] else {
                result(FlutterError(code: "IllegalArgument", message: "Unknown deviceId:\(deviceId)", details: nil))
                return
            }
            if (peripheral.state != .disconnected) {
                manager.cancelPeripheralConnection(peripheral)
            }
            result(nil)
        case "discoverServices":
            let arguments = call.arguments as! Dictionary<String, Any>
            let deviceId = arguments["deviceId"] as! String
            guard let peripheral = discoveredPeripherals[deviceId] else {
                result(FlutterError(code: "IllegalArgument", message: "Unknown deviceId:\(deviceId)", details: nil))
                return
            }
            peripheral.discoverServices(nil)
            result(nil)
        case "setNotifiable":
            let arguments = call.arguments as! Dictionary<String, Any>
            let deviceId = arguments["deviceId"] as! String
            var service = arguments["service"] as! String
            var characteristic = arguments["characteristic"] as! String
            let bleInputProperty = arguments["bleInputProperty"] as! String
            
            service = ensureX(service)
            characteristic = ensureX(characteristic)
            
            guard let peripheral = discoveredPeripherals[deviceId] else {
                // print("setNotifiable no 1 \(bleInputProperty != "disabled") \(service) \(characteristic)")
                result(FlutterError(code: "IllegalArgument", message: "Unknown deviceId:\(deviceId)", details: nil))
                return
            }
            guard let c = peripheral.getCharacteristic(characteristic, of: service) else {
                // print("setNotifiable no 2 \(bleInputProperty != "disabled") \(service) \(characteristic)")
                result(FlutterError(code: "IllegalArgument", message: "Unknown service's:\(service) characteristic:\(characteristic)", details: nil))
                return
            }
            // print("setNotifiable yes \(bleInputProperty != "disabled") \(service) \(characteristic)")
            peripheral.setNotifyValue(bleInputProperty != "disabled", for: c)
            result(nil)
        case "readValue":
            let arguments = call.arguments as! Dictionary<String, Any>
            let deviceId = arguments["deviceId"] as! String
            var service = arguments["service"] as! String
            var characteristic = arguments["characteristic"] as! String
            
            service = ensureX(service)
            characteristic = ensureX(characteristic)

            guard let peripheral = discoveredPeripherals[deviceId] else {
                result(FlutterError(code: "IllegalArgument", message: "Unknown deviceId:\(deviceId)", details: nil))
                return
            }
            guard let c = peripheral.getCharacteristic(characteristic, of: service) else {
                result(FlutterError(code: "IllegalArgument", message: "Unknown service's:\(service) characteristic:\(characteristic)", details: nil))
                return
            }
            peripheral.readValue(for: c)
            result(nil)
        case "writeValue":
            let arguments = call.arguments as! Dictionary<String, Any>
            let deviceId = arguments["deviceId"] as! String
            var service = arguments["service"] as! String
            var characteristic = arguments["characteristic"] as! String
            let value = arguments["value"] as! FlutterStandardTypedData
            let bleOutputProperty = arguments["bleOutputProperty"] as! String

            service = ensureX(service)
            characteristic = ensureX(characteristic)

            guard let peripheral = discoveredPeripherals[deviceId] else {
                result(FlutterError(code: "IllegalArgument", message: "Unknown deviceId:\(deviceId)", details: nil))
                return
            }
            let type = bleOutputProperty == "withoutResponse" ? CBCharacteristicWriteType.withoutResponse : CBCharacteristicWriteType.withResponse
            guard let c = peripheral.getCharacteristic(characteristic, of: service) else {
                result(FlutterError(code: "IllegalArgument", message: "Unknown service's:\(service) characteristic:\(characteristic)", details: nil))
                return
            }
            peripheral.writeValue(value.data, for: c, type: type)
            result(nil)
        case "requestMtu":
            let arguments = call.arguments as! Dictionary<String, Any>
            let deviceId = arguments["deviceId"] as! String
            guard let peripheral = discoveredPeripherals[deviceId] else {
                result(FlutterError(code: "IllegalArgument", message: "Unknown deviceId:\(deviceId)", details: nil))
                return
            }
            result(nil)
            let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
            // print("peripheral.maximumWriteValueLengthForType:CBCharacteristicWriteWithoutResponse \(mtu)")
            messageConnector.sendMessage(["mtuConfig": mtu + GATT_HEADER_LENGTH])
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

extension QuickBlueDarwin: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        availabilityChangeSink?(central.state.rawValue)
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // print("centralManager:didDiscoverPeripheral \(peripheral.name ?? "nil") \(peripheral.uuid.uuidString)")
        discoveredPeripherals[peripheral.uuid.uuidString] = peripheral

        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        scanResultSink?([
            "name": peripheral.name ?? "",
            "deviceId": peripheral.uuid.uuidString,
            "manufacturerData": FlutterStandardTypedData(bytes: manufacturerData ?? Data()),
            "rssi": RSSI,
        ])
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // print("centralManager:didConnect \(peripheral.uuid.uuidString)")
        messageConnector.sendMessage([
            "deviceId": peripheral.uuid.uuidString,
            "ConnectionState": "connected",
        ])
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // print("centralManager:didDisconnectPeripheral: \(peripheral.uuid.uuidString) error: \(String(describing: error))")
        messageConnector.sendMessage([
            "deviceId": peripheral.uuid.uuidString,
            "ConnectionState": "disconnected",
        ])
    }
}

extension QuickBlueDarwin: FlutterStreamHandler {
    open func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        guard let args = arguments as? Dictionary<String, Any>, let name = args["name"] as? String else {
            return nil
        }
        print("QuickBlueDarwin onListenWithArguments: \(name)")
        if name == "availabilityChange" {
            availabilityChangeSink = events
            availabilityChangeSink?(manager.state.rawValue) // Initializes CBCentralManager and returns the current state when hot restarting
        } else if name == "scanResult" {
            scanResultSink = events
        }
        return nil
    }

    open func onCancel(withArguments arguments: Any?) -> FlutterError? {
        guard let args = arguments as? Dictionary<String, Any>, let name = args["name"] as? String else {
            return nil
        }
        print("QuickBlueDarwin onCancelWithArguments: \(name)")
        if name == "availabilityChange" {
            availabilityChangeSink = nil
        } else if name == "scanResult" {
            scanResultSink = nil
        }
        return nil
    }
}

extension QuickBlueDarwin: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        // print("didUpdateNotificationStateFor \(characteristic) \(error)")
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        // print("peripheral: \(peripheral.uuid.uuidString) didDiscoverServices error: \(String(describing: error))")
        for service in peripheral.services! {
            // if service.uuid == CBUUID(string: "FF00") {
                peripheral.discoverCharacteristics(nil, for: service)
            // }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let s = peripheral.service2x(service: service)
        let cs = service.characteristics!.map { peripheral.characteristic2x(characteristic: $0) } //MISC This is a little wasteful compared to doing them all in one go
        // for characteristic in service.characteristics! {
        //     print("peripheral:didDiscoverCharacteristicsForService (\(service.uuid.uuidStr), \(characteristic.uuid.uuidStr)")
        // }
        
//         for characteristic in service.characteristics! {
//             print("Discovered characteristic \(characteristic.uuid)")
//        
//             peripheral.discoverDescriptors(for: characteristic)
//             
////             if characteristic.properties.contains(.notify) {
////                 print("Subscribing to \(characteristic.uuid)")
////                 peripheral.setNotifyValue(true, for: characteristic)
////             }
//         }

        self.messageConnector.sendMessage([
            "deviceId": peripheral.uuid.uuidString,
            "ServiceState": "discovered",
            "service": s as Any,
            "characteristics": cs
        ])
    }
    
//    public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
//        print("Discovered descriptors for characteristic \(characteristic.uuid)")
//   
//        for descriptor in characteristic.descriptors ?? [] {
//            peripheral.readValue(for: descriptor)
//        }
//    }
//    
//    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
//        print("didUpdateValueFor descriptor cu:\(descriptor.characteristic?.uuid) d:\(descriptor) du:\(descriptor.uuid) dv:\(descriptor.value) dvt:\(type(of: descriptor.value ?? ""))")
//        if let n = descriptor.value as? NSNumber {
//            print("dva:\(n)")
//        } else if let nsData = descriptor.value as? NSData {
//            let data = Data(referencing: nsData)
//            let str = String(data: data, encoding: String.Encoding.utf8)
//            print("dva:\(str)")
//        } else {
//            print("dva dunno")
//        }
//    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let s = peripheral.service2x(service: characteristic.service!) //DUMMY Why would service be null?  Do we need to worry?
        let c = peripheral.characteristic2x(characteristic: characteristic)
        // let data = characteristic.value as NSData?
        // print("peripheral:didWriteValueForCharacteristic \(characteristic.uuid.uuidStr) \(String(describing: data)) error: \(String(describing: error))")
        self.messageConnector.sendMessage([
            "deviceId": peripheral.uuid.uuidString,
            "wroteCharacteristicValue": [
                "service": s,
                "characteristic": c,
                "value": characteristic.value != nil ? FlutterStandardTypedData(bytes: characteristic.value!) : nil,
                "success": error == nil
            ]
        ])
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let s = peripheral.service2x(service: characteristic.service!) //DUMMY Why would service be null?  Do we need to worry?
        let c = peripheral.characteristic2x(characteristic: characteristic)
        // let data = characteristic.value as NSData?
        // print("peripheral:didUpdateValueForCharacteristic \(characteristic.uuid) \(String(describing: data)) error: \(String(describing: error))")
        if let error {
            print("peripheral:didUpdateValueForCharacteristic \(characteristic.uuid) \(String(describing: characteristic.value)) error: \(String(describing: error))")
        }
        self.messageConnector.sendMessage([
            "deviceId": peripheral.uuid.uuidString,
            "characteristicValue": [
                "service": s as Any,
                "characteristic": c as Any,
                "value": (characteristic.value == nil ? nil : FlutterStandardTypedData(bytes: characteristic.value!)) as Any
            ]
        ])
    }
}
