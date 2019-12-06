import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_phone_state/extensions_static.dart';
import 'package:flutter_phone_state/logging.dart';
import 'package:flutter_phone_state/phone_event.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

export 'package:flutter_phone_state/phone_event.dart';

/// Phone events created by this plugin
final _localEvents = StreamController<PhoneCallEvent>.broadcast();
const MethodChannel _channel = MethodChannel('flutter_phone_state');

final Logger _log = Logger("flutterPhoneState");
final _instance = FlutterPhoneState();

class FlutterPhoneState with WidgetsBindingObserver {
  /// Configures logging.  FlutterPhoneState uses the [logging] plugin.
  static void configureLogs({Level level, Logging onLog}) {
    configureLogging(logger: _log, level: level, onLog: onLog);
  }

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  /// A broadcast stream of raw events from the underlying phone state.  It's preferred to use [phoneCallEvents]
  static Stream<RawPhoneEvent> get rawPhoneEvents => _initializedNativeEvents;

  /// A list of events associated to all calls.  This includes events from the underlying OS, as well as our
  /// own cancellation and timeout errors
  static Stream<PhoneCallEvent> get phoneCallEvents => _localEvents.stream;

  /// Places a phone call.  This will initiate a call on the target OS.
  /// The [PhoneCall] can be used to subscribe to events, or to await completion.  See
  /// see [PhoneCall.done] or [PhoneCall.eventStream]
  static PhoneCall startPhoneCall(String phoneNumber) {
    return _instance._makePhoneCall(phoneNumber);
  }

  /// Returns a list of active calls.
  static Iterable<PhoneCall> get activeCalls => [..._instance._calls];

  FlutterPhoneState() {
    configureLogging(logger: _log);
    WidgetsBinding.instance.addObserver(this);
    _initializedNativeEvents.forEach(_handleRawPhoneEvent);
  }

  /// A list of active calls.  Theoretically, you could initiate a call while the first is still in flight.
  /// This should add both calls, and track them separately as best we can.
  ///
  /// As a note, Android does not support listening to events from nested calls.
  List<PhoneCall> _calls = <PhoneCall>[];

  /// Finds a previously placed call that matches the incoming event
  PhoneCall _findMatchingCall(RawPhoneEvent event) {
    // Either the first matching, or the first one without an ID
    PhoneCall matching;
    if (event.id != null) {
      matching = firstOrNull(_calls, (c) => c.callId == event.id);
    }
    matching ??= lastOrNull(_calls, (call) => call.canBeLinked(event));
    if (matching != null) {
      // Link them together for future reference
      matching.callId = event.id;
    }
    return matching;
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log.info("Received application lifecycle state change: $state");

    if (state == AppLifecycleState.resumed) {
      /// We wait 1 second because ios has a short flash of resumed before the phone app opens
      Future.delayed(Duration(seconds: 1), () {
        final expired = lastOrNull<PhoneCall>(_calls, (PhoneCall c) {
          return c.status == PhoneCallStatus.dialing &&
              sinceNow(c.startTime).inSeconds < 30;
        });

        if (expired != null) {
          _changeStatus(expired, PhoneCallStatus.cancelled);
        }
      });
    }
  }

  _openCallLink(PhoneCall call) async {
    /// Phone calls are weird in IOS.  We need to initiate the phone call by using the link
    /// below, but the app doesn't give us any meaningful feedback, so we mark the phone interaction
    /// as "complete" (technically this just means the call was started) by either
    /// (a) the applicationStateChange recognizing a return to the app
    /// (b) the event handler above fires with a call start event within 30 seconds
    /// (c) 5 seconds passes with no feedback (this will send back a result code of [cancelled], which
    ///     means the call won't be logged
    try {
      final link = "tel:${call.phoneNumber}";
      final status = await _openTelLink(link);

      if (status != LinkOpenResult.success) {
        _changeStatus(call, PhoneCallStatus.error);
        return;
      }

      /// If no activity reported within 10 seconds, we'll cancel the call
      await Future.delayed(Duration(seconds: 60));

      if (call.status == PhoneCallStatus.dialing) {
        _changeStatus(call, PhoneCallStatus.timedOut);
      }
    } catch (e) {
      _changeStatus(call, PhoneCallStatus.error);
    }
  }

  PhoneCall _makePhoneCall(String phoneNumber) {
    final call = PhoneCall.start(phoneNumber, PhoneCallPlacement.outbound);
    _calls.add(call);
    _changeStatus(call, PhoneCallStatus.dialing);
    _openCallLink(call);
    return call;
  }

  void _changeStatus(PhoneCall call, PhoneCallStatus status) {
    // create an event
    PhoneCallEvent event;
    if (call.events.any((e) => e.status == status)) {
      _log.fine("Call ${truncate(call.id, 8)} already has status $status");
    }
    if (status == PhoneCallStatus.disconnected ||
        status == PhoneCallStatus.timedOut ||
        status == PhoneCallStatus.error ||
        status == PhoneCallStatus.cancelled) {
      _log.info("Call is done: ${call.id}- Removing due to $status");
      call.complete(status).then((event) {
        _localEvents.add(event);
      });
      _calls.removeWhere((existing) => existing == call);
    } else {
      event = call.recordStatus(status);
      _localEvents.add(event);
    }
  }

  _handleRawPhoneEvent(RawPhoneEvent event) async {
    try {
      _pruneCalls();
      PhoneCall matching = _findMatchingCall(event);

      /// If no match was found?
      if (matching == null && event.isNewCall) {
        _log.info("Adding a call to the stack: $event");
        matching = PhoneCall.start(
          event.phoneNumber,
          event.type == RawEventType.inbound
              ? PhoneCallPlacement.inbound
              : PhoneCallPlacement.outbound,
          event.id,
        );
        _calls.add(matching);
        _changeStatus(
            matching,
            matching.isInbound
                ? PhoneCallStatus.ringing
                : PhoneCallStatus.dialing);
        return;
      }

      if (matching == null) {
        // Nothing else we can do here...
        return;
      }
      switch (event.type) {
        case RawEventType.inbound:
          // Nothing
          break;
        case RawEventType.outbound:
          _changeStatus(matching, PhoneCallStatus.connecting);
          break;
        case RawEventType.connected:
          _changeStatus(matching, PhoneCallStatus.connected);
          break;
        case RawEventType.disconnected:

          /// We ended the call--- makes sure it's not some ridiculously long call
          _changeStatus(matching, PhoneCallStatus.disconnected);
          break;
      }
    } catch (e, stack) {
      _log.severe("Error handling phone call event: $e", e, stack);
    }
  }

  /// Looks for calls that weren't properly terminated and completes them
  _pruneCalls() {
    final expired = [..._calls.where((c) => c.isExpired)];
    for (final expiring in expired) {
      _changeStatus(expiring, PhoneCallStatus.timedOut);
    }
  }
}

/// The event channel to receive native phone events
final EventChannel _phoneStateCallEventChannel =
    EventChannel('co.sunnyapp/phone_events');

/// Native event stream, lazily created.  See [nativeEvents]
Stream<RawPhoneEvent> _nativeEvents;

/// A stream of [RawPhoneEvent] instances.  The stream only contains null values if there was an error
Stream<RawPhoneEvent> get _initializedNativeEvents {
  _nativeEvents ??=
      _phoneStateCallEventChannel.receiveBroadcastStream().map((dyn) {
    try {
      if (dyn == null) return null;
      if (dyn is! Map) {
        _log.warning("Unexpected result type for phone event.  "
            "Expected Map<String, dynamic> but got ${dyn?.runtimeType ?? 'null'} ");
      }
      final Map<String, dynamic> event = (dyn as Map).cast();
      final eventType = _parseEventType(event["type"] as String);
      return RawPhoneEvent(
          event["id"] as String, event["phoneNumber"] as String, eventType);
    } catch (e, stack) {
      _log.severe("Error handling native event $e", e, stack);
      return null;
    }
  });
  return _nativeEvents;
}

RawEventType _parseEventType(String dyn) {
  switch (dyn) {
    case "inbound":
      return RawEventType.inbound;
    case "connected":
      return RawEventType.connected;
    case "outbound":
      return RawEventType.outbound;
    case "disconnected":
      return RawEventType.disconnected;
    default:
      throw "Illegal raw event type: $dyn";
  }
}

/// Removes all non-numeric characters
String sanitizePhoneNumber(String input) {
  String out = "";

  for (var i = 0; i < input.length; ++i) {
    var char = input[i];
    if (_isNumeric((char))) {
      out += char;
    }
  }
  return out;
}

bool _isNumeric(String str) {
  if (str == null) {
    return false;
  }
  return double.tryParse(str) != null;
}

Future<LinkOpenResult> _openTelLink(String appLink) async {
  if (appLink == null) {
    return LinkOpenResult.invalidInput;
  }
  if (await canLaunch(appLink)) {
    return (await launch(appLink))
        ? LinkOpenResult.success
        : LinkOpenResult.failed;
  } else {
    return LinkOpenResult.unsupported;
  }
}

enum LinkOpenResult { invalidInput, unsupported, success, failed }
