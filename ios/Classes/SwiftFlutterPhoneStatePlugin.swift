import Flutter
import UIKit
import CallKit

@available(iOS 10.0, *)
public class SwiftFlutterPhoneStatePlugin: NSObject, CXCallObserverDelegate, FlutterPlugin, FlutterStreamHandler {
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        return nil
    }
    
    private func sendEvent(event:PhoneEvent) {
        if eventSink != nil {
            eventSink(event.toDict())
        }
    }
    
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_phone_state", binaryMessenger: registrar.messenger())
        let instance = SwiftFlutterPhoneStatePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        let events = FlutterEventChannel(name: "co.sunnyapp/phone_events", binaryMessenger: registrar.messenger())
        events.setStreamHandler(instance)
    }
    
    let callObserver: CXCallObserver
    var eventSink: FlutterEventSink!
    
    public func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        
        
        if call.hasEnded == true {
            sendEvent(event: PhoneEvent(phoneNumber: nil,
                                        type: "disconnected",
                                        id: call.uuid.uuidString))
        }
        
        if call.isOutgoing == true && call.hasConnected == false {
            sendEvent(event: PhoneEvent(phoneNumber: nil,
            type: "outbound",
            id: call.uuid.uuidString))
        }
        
        if call.isOutgoing == false && call.hasConnected == false && call.hasEnded == false {
            sendEvent(event: PhoneEvent(phoneNumber: nil,
            type: "inbound",
            id: call.uuid.uuidString))
        }
        
        if call.hasConnected == true && call.hasEnded == false {
            sendEvent(event: PhoneEvent(phoneNumber: nil,
            type: "connected",
            id: call.uuid.uuidString))
        }
    }
    
    public override init() {
        callObserver = CXCallObserver()
        super.init()
        callObserver.setDelegate(self, queue: DispatchQueue.main)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        result("iOS " + UIDevice.current.systemVersion)
    }
}

public struct PhoneEvent {
    let phoneNumber: String?
    let type: String
    let id: String
    
    func toDict() -> [String: String] {
        var d = [String:String]()
        if phoneNumber != nil {
            d["phoneNumber"] = phoneNumber
        }
        d["type"] = type
        d["id"] = id
        return d
    }
}

