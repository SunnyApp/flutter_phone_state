package co.sunnyapp.flutter_phone_state

import android.content.Context
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import io.flutter.plugin.common.EventChannel
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import androidx.annotation.NonNull

class FlutterPhoneStatePlugin: FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var channel: MethodChannel
    private lateinit var eventSink: EventChannel
    private lateinit var binding: FlutterPlugin.FlutterPluginBinding

    private val telephonyManager = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager

    /// So it doesn't get collected
    private lateinit var listener:PhoneStateListener

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        binding = flutterPluginBinding;
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_phone_state")  
        channel.setMethodCallHandler(this)
        eventSink = EventChannel(flutterPluginBinding.binaryMessenger, "co.sunnyapp/phone_events")
        eventSink.setStreamHandler(this)
    }


    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        listener = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method == "getPlatformVersion") {
            result.success("Android ${android.os.Build.VERSION.RELEASE}")
        } else {
            result.notImplemented()
        }
    }


    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (events == null) return

        this.listener = object : PhoneStateListener() {
            override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                when (state) {
                    /** Device call state: No activity.  */
                    TelephonyManager.CALL_STATE_IDLE -> {
                        events.success(PhoneCallEvent(phoneNumber, PhoneEventType.disconnected).toMap())
                    }
                    /** Device call state: Off-hook. At least one call exists
                     * that is dialing, active, or on hold, and no calls are ringing
                     * or waiting. */
                    TelephonyManager.CALL_STATE_OFFHOOK -> {
                        events.success(PhoneCallEvent(phoneNumber, PhoneEventType.connected).toMap())
                    }
                    /** Device call state: Ringing. A new call arrived and is
                     * ringing or waiting. In the latter case, another call is
                     * already active.  */
                    TelephonyManager.CALL_STATE_RINGING -> {
                        events.success(PhoneCallEvent(phoneNumber, PhoneEventType.inbound).toMap())
                    }
                }
            }
        }
        telephonyManager.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
    }

    override fun onCancel(arguments: Any?) {
        // nothing to do
        print("Cancelling stream!")
    }
}

data class PhoneCallEvent(val phoneNumber: String? = null, val type: PhoneEventType) {
    fun toMap(): Map<String, String> {
        val map = mutableMapOf<String, String>()
        if (phoneNumber?.isNotBlank() == true) {
            map["phoneNumber"] = phoneNumber
            map["id"] = phoneNumber
        }
        map["type"] = type.name
        return map
    }
}

enum class PhoneEventType {
    inbound,
    connected,
    disconnected
}
