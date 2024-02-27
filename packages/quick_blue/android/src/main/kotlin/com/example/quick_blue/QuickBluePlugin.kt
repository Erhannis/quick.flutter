package com.example.quick_blue

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import androidx.annotation.NonNull
import io.flutter.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.*
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.*


private const val TAG = "QuickBluePlugin"

typealias XString = String

/** QuickBluePlugin */
@SuppressLint("MissingPermission")
class QuickBluePlugin: FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var method : MethodChannel
  private lateinit var eventAvailabilityChange : EventChannel
  private lateinit var eventScanResult : EventChannel
  private lateinit var messageConnector: BasicMessageChannel<Any>

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    method = MethodChannel(flutterPluginBinding.binaryMessenger, "quick_blue/method")
    eventAvailabilityChange = EventChannel(flutterPluginBinding.binaryMessenger, "quick_blue/event.availabilityChange")
    eventScanResult = EventChannel(flutterPluginBinding.binaryMessenger, "quick_blue/event.scanResult")
    messageConnector = BasicMessageChannel(flutterPluginBinding.binaryMessenger, "quick_blue/message.connector", StandardMessageCodec.INSTANCE)
    method.setMethodCallHandler(this)
    eventAvailabilityChange.setStreamHandler(this)
    eventScanResult.setStreamHandler(this)

    context = flutterPluginBinding.applicationContext
    mainThreadHandler = Handler(Looper.getMainLooper())
    bluetoothManager = flutterPluginBinding.applicationContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager

    context.registerReceiver(
      broadcastReceiver,
      IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
    )

  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    bluetoothManager.adapter.bluetoothLeScanner?.stopScan(scanCallback)

    context.unregisterReceiver(broadcastReceiver)
    eventAvailabilityChange.setStreamHandler(null)
    eventScanResult.setStreamHandler(null)
    method.setMethodCallHandler(null)
  }

  private lateinit var context: Context
  private lateinit var mainThreadHandler: Handler
  private lateinit var bluetoothManager: BluetoothManager

  private val knownGatts = mutableListOf<BluetoothGatt>()

  private fun sendMessage(messageChannel: BasicMessageChannel<Any>, message: Map<String, Any>) {
    mainThreadHandler.post { messageChannel.send(message) }
  }

  fun trace() = Arrays.toString(Throwable().stackTrace)

  fun x2ss(@NonNull xs: XString): String {
    val i = xs.indexOf(":")
    if (i == -1) {
      return xs.uppercase()
    } else {
      return xs.substring(0, i).uppercase()
    }
  }

  fun x2si(@NonNull xs: XString): Int? {
    val i = xs.indexOf(":")
    if (i == -1) {
      return 0 //DUMMY //CHECK Not sure about this one
    } else {
      try {
        return Integer.parseInt(xs.substring(i + 1))
      } catch (e: Exception) {
        return null
      }
    }
  }

  fun s2x(s: String, i: Int = 0): XString {
    val s = s.uppercase() //DUMMY Hmmmmmm, I'm not sure about this, could conflict with native uuids
    return "$s:$i"
  }

  fun ensureX(s: String): XString {
    val s = s.uppercase() //DUMMY Hmmmmmm, I'm not sure about this, could conflict with native uuids
    val i = s.indexOf(":")
    return if (i == -1) {
      "$s:0"
    } else {
      s
    }
  }

  fun x2service(@NonNull services: List<BluetoothGattService>, @NonNull service: XString): BluetoothGattService? {
    var service = ensureX(service)
    val ss: MutableMap<String, Int> = mutableMapOf()
    for (x in services) {
      val k = "${x.uuid}"
      if (!ss.containsKey(k)) {
        ss[k] = -1
      }
      ss[k] = (ss[k]!!) + 1
      var sxi = ss[k]!!
      var sxs = s2x(k, sxi)

      if (sxs.contentEquals(service)) {
        Log.e(TAG, "x2serv yes $sxs $service")
        return x
      }
      Log.e(TAG, "x2serv no $sxs $service")
    }
    return null
  }

  fun x2characteristic(@NonNull characteristics: List<BluetoothGattCharacteristic>, @NonNull characteristic: XString): BluetoothGattCharacteristic? {
    var characteristic = ensureX(characteristic)
    val cs: MutableMap<String, Int> = mutableMapOf()
    for (x in characteristics) {
      val k = "${x.uuid}"
      if (!cs.containsKey(k)) {
        cs[k] = -1
      }
      cs[k] = (cs[k]!!) + 1
      var cxi = cs[k]!!
      var cxs = s2x(k, cxi)

      if (cxs.contentEquals(characteristic)) {
        Log.e(TAG, "x2char yes $cxs $characteristic")
        return x
      }
      Log.e(TAG, "x2char no $cxs $characteristic")
    }
    return null
  }

  fun service2x(@NonNull gatt: BluetoothGatt, @NonNull service: BluetoothGattService): XString? {
    val ss: MutableMap<String, Int> = mutableMapOf()
    for (x in gatt.services) {
      val k = "${x.uuid}"
      if (!ss.containsKey(k)) {
        ss[k] = -1
      }
      ss[k] = (ss[k]!!) + 1
      var sxi = ss[k]!!
      var sxs = s2x(k, sxi)

      if (x.uuid.equals(service.uuid) && x.instanceId == service.instanceId) {
        return sxs
      }
    }
    return null
  }

  fun characteristic2x(@NonNull characteristic: BluetoothGattCharacteristic): XString? {
    val cs: MutableMap<String, Int> = mutableMapOf()
    for (x in characteristic.service.characteristics) {
      val k = "${x.uuid}"
      if (!cs.containsKey(k)) {
        cs[k] = -1
      }
      cs[k] = (cs[k]!!) + 1
      var cxi = cs[k]!!
      var cxs = s2x(k, cxi)

      if (x.uuid.equals(characteristic.uuid) && x.instanceId == characteristic.instanceId) {
        return cxs
      }
    }
    return null
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    try {
      when (call.method) {
        "isBluetoothAvailable" -> {
          result.success(bluetoothManager.adapter.isEnabled)
        }
        "startScan" -> {
          val serviceUUIDs = call.argument<ArrayList<String>>("serviceUUIDs") //DUMMY Note String not XString
          if (serviceUUIDs != null && serviceUUIDs.size > 0) {
            val filters: ArrayList<ScanFilter> = ArrayList()
            for (serviceUUID in serviceUUIDs) {
              val filter = ScanFilter.Builder()
                      .setServiceUuid(parseToParcelUuid(serviceUUID))
                      .build()
              filters.add(filter)
            }

            val settings = ScanSettings.Builder()
                    .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                    .build()

            bluetoothManager.adapter.bluetoothLeScanner?.startScan(filters, settings, scanCallback)
          } else {
            bluetoothManager.adapter.bluetoothLeScanner?.startScan(scanCallback)
          }
          result.success(null)
        }
        "stopScan" -> {
          bluetoothManager.adapter.bluetoothLeScanner?.stopScan(scanCallback)
          result.success(null)
        }
        "connect" -> {
          val deviceId = call.argument<String>("deviceId")!!
          if (knownGatts.find { it.device.address == deviceId } != null) {
            return result.success(null)
          }
          val remoteDevice = bluetoothManager.adapter.getRemoteDevice(deviceId)
          val gatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            remoteDevice.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
          } else {
            remoteDevice.connectGatt(context, false, gattCallback)
          }
          knownGatts.add(gatt)
          result.success(null)
          // TODO connecting
        }
        "disconnect" -> {
          val deviceId = call.argument<String>("deviceId")!!
          val gatt = knownGatts.find { it.device.address == deviceId }
                  ?: return result.error("IllegalArgument", "Unknown deviceId: $deviceId", trace())
          cleanConnection(gatt)
          result.success(null)
          //FIXME If `disconnect` is called before BluetoothGatt.STATE_CONNECTED
          // there will be no `disconnected` message any more
        }
        "discoverServices" -> {
          val deviceId = call.argument<String>("deviceId")!!
          val gatt = knownGatts.find { it.device.address == deviceId }
                  ?: return result.error("IllegalArgument", "Unknown deviceId: $deviceId", trace())
          gatt.discoverServices()
          result.success(null)
        }
        "setNotifiable" -> {
          val deviceId = call.argument<String>("deviceId")!!
          var service = call.argument<XString>("service")!!
          var characteristic = call.argument<XString>("characteristic")!!
          val bleInputProperty = call.argument<String>("bleInputProperty")!!

          Log.e(TAG, "setNotifiable $service $characteristic")

          service = ensureX(service)
          characteristic = ensureX(characteristic)

          val gatt = knownGatts.find { it.device.address == deviceId }
                  ?: return result.error("IllegalArgument", "Unknown deviceId: $deviceId", trace())
          val s = x2service(gatt.services, service)
                  ?: return result.error("IllegalArgument", "Unknown service: $service", trace())
          val c = x2characteristic(s.characteristics, characteristic)
                  ?: return result.error("IllegalArgument", "Unknown characteristic: $characteristic", trace())
          gatt.setNotifiable(c, bleInputProperty)
          result.success(null)
        }
        "readValue" -> {
          val deviceId = call.argument<String>("deviceId")!!
          var service = call.argument<XString>("service")!!
          var characteristic = call.argument<XString>("characteristic")!!

          service = ensureX(service)
          characteristic = ensureX(characteristic)

          val gatt = knownGatts.find { it.device.address == deviceId }
                  ?: return result.error("IllegalArgument", "Unknown deviceId: $deviceId", trace())
          val s = x2service(gatt.services, service)
                  ?: return result.error("IllegalArgument", "Unknown service: $service", trace())
          val c = x2characteristic(s.characteristics, characteristic)
                  ?: return result.error("IllegalArgument", "Unknown characteristic: $characteristic", trace())
          if (gatt.readCharacteristic(c))
            result.success(null)
          else
            result.error("Characteristic unavailable", null, trace())
        }
        "writeValue" -> {
          val deviceId = call.argument<String>("deviceId")!!
          var service = call.argument<XString>("service")!!
          var characteristic = call.argument<XString>("characteristic")!!
          val value = call.argument<ByteArray>("value")!!

          service = ensureX(service)
          characteristic = ensureX(characteristic)

          val gatt = knownGatts.find { it.device.address == deviceId }
                  ?: return result.error("IllegalArgument", "Unknown deviceId: $deviceId", trace())
          val s = x2service(gatt.services, service)
                  ?: return result.error("IllegalArgument", "Unknown service: $service", trace())
          val c = x2characteristic(s.characteristics, characteristic)
                  ?: return result.error("IllegalArgument", "Unknown characteristic: $characteristic", trace())
          c.value = value
          if (gatt.writeCharacteristic(c)) {
            result.success(null)
          } else {
            result.error("Characteristic unavailable", null, trace())
          }
        }
        "requestMtu" -> {
          val deviceId = call.argument<String>("deviceId")!!
          val expectedMtu = call.argument<Int>("expectedMtu")!!
          val gatt = knownGatts.find { it.device.address == deviceId }
                  ?: return result.error("IllegalArgument", "Unknown deviceId: $deviceId", trace())
          val success = gatt.requestMtu(expectedMtu)
          if (success)
            result.success(null)
          else
            result.error("Unable to set MTU", null, trace())
        }
        else -> {
          result.notImplemented()
        }
      }
    } catch (e: Throwable) {
      e.printStackTrace()
      result.error("Error", "Error", trace())
    }
  }

  private fun cleanConnection(gatt: BluetoothGatt) {
    gatt.close()
    gatt.disconnect()
    knownGatts.remove(gatt)
  }

  enum class AvailabilityState(val value: Int) {
    unknown(0),
    resetting(1),
    unsupported(2),
    unauthorized(3),
    poweredOff(4),
    poweredOn(5),
  }

  fun BluetoothManager.getAvailabilityState(): AvailabilityState {
    val state = adapter?.state ?: return AvailabilityState.unsupported
    return when(state) {
      BluetoothAdapter.STATE_OFF -> AvailabilityState.poweredOff
      BluetoothAdapter.STATE_ON -> AvailabilityState.poweredOn
      BluetoothAdapter.STATE_TURNING_ON -> AvailabilityState.resetting
      BluetoothAdapter.STATE_TURNING_OFF -> AvailabilityState.resetting
      else -> AvailabilityState.unknown
    }
  }

  private val broadcastReceiver = object : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent?.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
          availabilityChangeSink?.success(bluetoothManager.getAvailabilityState().value)
        }
    }
  }

  private val scanCallback = object : ScanCallback() {
    override fun onScanFailed(errorCode: Int) {
      //Log.v(TAG, "onScanFailed: $errorCode")
    }

    override fun onScanResult(callbackType: Int, result: ScanResult) {
      scanResultSink?.success(mapOf<String, Any>(
              "name" to (result.device.name ?: ""),
              "deviceId" to result.device.address,
              "manufacturerDataHead" to (result.manufacturerDataHead ?: byteArrayOf()),
              "rssi" to result.rssi
      ))
    }

    override fun onBatchScanResults(results: MutableList<ScanResult>?) {
      //Log.v(TAG, "onBatchScanResults: $results")
    }
  }

  private var availabilityChangeSink: EventChannel.EventSink? = null
  private var scanResultSink: EventChannel.EventSink? = null

  override fun onListen(args: Any?, eventSink: EventChannel.EventSink?) {
    val map = args as? Map<String, Any> ?: return
    when (map["name"]) {
      "availabilityChange" -> {
        availabilityChangeSink = eventSink
        availabilityChangeSink?.success(bluetoothManager.getAvailabilityState().value)
      }
      "scanResult" -> scanResultSink = eventSink
    }
  }

  override fun onCancel(args: Any?) {
    val map = args as? Map<String, Any> ?: return
    when (map["name"]) {
      "availabilityChange" -> availabilityChangeSink = null
      "scanResult" -> scanResultSink = null
    }
  }

  private val gattCallback = object : BluetoothGattCallback() {
    override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
      //Log.v(TAG, "onConnectionStateChange: device(${gatt.device.address}) status($status), newState($newState)")
      if (newState == BluetoothGatt.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
        sendMessage(messageConnector, mapOf(
          "deviceId" to gatt.device.address,
          "ConnectionState" to "connected"
        ))
      } else {
        cleanConnection(gatt)
        sendMessage(messageConnector, mapOf(
          "deviceId" to gatt.device.address,
          "ConnectionState" to "disconnected"
        ))
      }
    }

    override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
      //Log.v(TAG, "onServicesDiscovered ${gatt.device.address} $status")
      if (status != BluetoothGatt.GATT_SUCCESS) return

      val ss: MutableMap<String, Int> = mutableMapOf()
      gatt.services?.forEach { service ->
        //Log.v(TAG, "Service " + service.uuid)
        service.characteristics.forEach { characteristic ->
          //Log.v(TAG, "    Characteristic ${characteristic.uuid}")
          characteristic.descriptors.forEach {
            //Log.v(TAG, "        Descriptor ${it.uuid}")
          }
        }

        val k = "${service.uuid}"
        if (!ss.containsKey(k)) {
          ss[k] = -1
        }
        ss[k] = (ss[k]!!) + 1
        var sxi = ss[k]!!
        var sxs = s2x(k, sxi)

        var characteristics: MutableList<XString> = mutableListOf()

        val cs: MutableMap<String, Int> = mutableMapOf()
        for (x in service.characteristics) {
          val k = "${x.uuid}"
          if (!cs.containsKey(k)) {
            cs[k] = -1
          }
          cs[k] = (cs[k]!!) + 1
          var cxi = cs[k]!!
          var cxs = s2x(k, cxi)

          characteristics.add(cxs)
        }

        sendMessage(messageConnector, mapOf(
          "deviceId" to gatt.device.address,
          "ServiceState" to "discovered",
          "service" to sxs,
          "characteristics" to characteristics
        ))
      }
    }

    override fun onMtuChanged(gatt: BluetoothGatt?, mtu: Int, status: Int) {
      if (status == BluetoothGatt.GATT_SUCCESS) {
        sendMessage(messageConnector, mapOf(
          "mtuConfig" to mtu
        ))
      } else {
        sendMessage(messageConnector, mapOf(
          "mtuConfig" to -1
        ))
      }
    }

    override fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
      //Log.v(TAG, "onCharacteristicRead ${characteristic.uuid}, ${characteristic.value.contentToString()}")

      val s = service2x(gatt, characteristic.service)
      val c = characteristic2x(characteristic)

      sendMessage(messageConnector, mapOf(
        "deviceId" to gatt.device.address,
        "characteristicValue" to mapOf(
          "service" to s,
          "characteristic" to c,
          "value" to characteristic.value
        )
      ))
    }

    override fun onCharacteristicWrite(gatt: BluetoothGatt?, characteristic: BluetoothGattCharacteristic, status: Int) {
      //Log.v(TAG, "onCharacteristicWrite ${characteristic.uuid}, ${characteristic.value.contentToString()} $status")

      val s = service2x(gatt!!, characteristic.service) //DUMMY Why would gatt be null?  Do we need to worry?
      val c = characteristic2x(characteristic)

      sendMessage(messageConnector, mapOf(
              "deviceId" to gatt!!.device.address,
              "wroteCharacteristicValue" to mapOf(
                      "service" to s,
                      "characteristic" to c,
                      "value" to characteristic.value,
                      "success" to (status == BluetoothGatt.GATT_SUCCESS)
              )
      ))
    }

    override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
      Log.e(TAG, "onCharacteristicChanged ${characteristic.uuid}/${characteristic.instanceId}, ${characteristic.value.contentToString()}")

      val s = service2x(gatt, characteristic.service)
      val c = characteristic2x(characteristic)

      sendMessage(messageConnector, mapOf(
        "deviceId" to gatt.device.address,
        "characteristicValue" to mapOf(
          "service" to s,
          "characteristic" to c,
          "value" to characteristic.value
        )
      ))
    }
  }
}

val ScanResult.manufacturerDataHead: ByteArray?
  get() {
    val sparseArray = scanRecord?.manufacturerSpecificData ?: return null
    if (sparseArray.size() == 0) return null

    return sparseArray.keyAt(0).toShort().toByteArray() + sparseArray.valueAt(0)
  }

fun Short.toByteArray(byteOrder: ByteOrder = ByteOrder.LITTLE_ENDIAN): ByteArray =
        ByteBuffer.allocate(2 /*Short.SIZE_BYTES*/).order(byteOrder).putShort(this).array()

private val DESC__CLIENT_CHAR_CONFIGURATION = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

fun BluetoothGatt.setNotifiable(gattCharacteristic: BluetoothGattCharacteristic, bleInputProperty: String) {
  Log.e(TAG, "setNotifiable ${gattCharacteristic.uuid}/${gattCharacteristic.instanceId}")

  val descriptor = gattCharacteristic.getDescriptor(DESC__CLIENT_CHAR_CONFIGURATION)
  val (value, enable) = when (bleInputProperty) {
    "notification" -> BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE to true
    "indication" -> BluetoothGattDescriptor.ENABLE_INDICATION_VALUE to true
    else -> BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE to false
  }
  if (setCharacteristicNotification(gattCharacteristic, enable) && descriptor != null) {
    descriptor.value = value
    writeDescriptor(descriptor)
    Log.e(TAG, "setNotifiable t")
  } else {
    Log.e(TAG, "setNotifiable f")
  }
}
const val baseBluetoothUuidPostfix = "0000-1000-8000-00805F9B34FB"

fun parseToParcelUuid(uuid: String): ParcelUuid {
  return when (uuid.length) {
      4 -> {
        ParcelUuid(UUID.fromString("0000$uuid-$baseBluetoothUuidPostfix"))
      }
      8 -> {
        ParcelUuid(UUID.fromString("$uuid-$baseBluetoothUuidPostfix"))
      }
      else -> {
        ParcelUuid.fromString(uuid)
      }
  }
}