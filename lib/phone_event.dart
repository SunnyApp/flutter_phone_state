import 'dart:async';

import 'package:flutter_phone_state/extensions_static.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

final Logger _log = Logger("flutterPhoneState");

/// Represents phone events that surface from the device.  These events can be subscribed to by
/// using [FlutterPhoneState.rawEventStream]
///
/// We recommend using [PhoneCallEvent]
class RawPhoneEvent {
  /// Underlying call ID assigned by the device.
  /// android: always null
  /// ios: a uuid
  /// others: ??
  final String id;

  /// If available, the phone number being dialed.
  final String phoneNumber;

  /// The type of call event.
  final RawEventType type;

  RawPhoneEvent(this.id, this.phoneNumber, this.type);

  /// Whether this event represents a new call
  bool get isNewCall =>
      type == RawEventType.inbound || type == RawEventType.outbound;

  @override
  String toString() {
    return 'RawPhoneEvent{type: ${value(type)}, id: ${truncate(id, 12) ?? '-'}, phoneNumber: ${phoneNumber ?? '-'}}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RawPhoneEvent &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          phoneNumber == other.phoneNumber &&
          type == other.type;

  @override
  int get hashCode => id.hashCode ^ phoneNumber.hashCode ^ type.hashCode;
}

/// An event surfaced from a phone call
class PhoneCallEvent {
  /// The call this event was attached to.
  /// @non_null
  final PhoneCall call;

  /// What status this event represents.
  /// @non_null
  final PhoneCallStatus status;

  /// Timestamp for this event
  /// @non_null
  final DateTime timestamp;

  PhoneCallEvent(this.call, this.status, [DateTime eventDate])
      : timestamp = eventDate ?? DateTime.now();

  @override
  String toString() {
    return 'PhoneCallEvent{status: ${value(status)}, '
        'id: ${truncate(call?.id, 12)} '
        'callId: ${truncate(call?.callId, 12) ?? '-'}, '
        'phoneNumber: ${call?.phoneNumber ?? '-'}}';
  }
}

/// A representation of a phone call lifecycle.  It's impossible to be precise, but we make a
/// best-ditch effort to link calls up
class PhoneCall {
  /// An id assigned by this plugin
  /// @non_null
  final String id;

  /// An id assigned to the call by the underlying os
  /// @nullable
  String callId;

  /// The phone number being dialed, or the inbound number
  /// @nullabe
  String phoneNumber;

  /// The current status of the call
  /// @non_null
  PhoneCallStatus status;

  /// Whether the call is inbound or outbound
  /// @non_null
  final PhoneCallPlacement placement;

  /// When the call was started
  final DateTime startTime;

  /// A list of events associated with this call
  final List<PhoneCallEvent> events;

  /// Whether or not this call is complete.  see [isComplete]
  bool _isComplete = false;

  /// Used internally to track the call events, can be subscribed to, or awaited on.
  StreamController<PhoneCallEvent> _eventStream;

  /// The final call duration.  See [duration]
  Duration _duration;

  PhoneCall.start(this.phoneNumber, this.placement, [String id])
      : status = null,
        id = id ?? Uuid().v4(),
        events = <PhoneCallEvent>[],
        startTime = DateTime.now();

  bool get isOutbound => placement == PhoneCallPlacement.outbound;

  bool get isInbound => placement == PhoneCallPlacement.inbound;

  /// Whether this call is complete
  bool get isComplete => _isComplete;

  /// Marks this call as complete, and returns the final event as a [FutureOr].  If the
  /// event stream has subscribers, it will first close, and then return
  Future<PhoneCallEvent> complete(PhoneCallStatus status) async {
    if (_isComplete) {
      throw "Illegal state: This call is already marked complete";
    }
    this._duration = DateTime.now().difference(startTime);
    final event = recordStatus(status);
    _isComplete = true;
    if (_eventStream?.isClosed == false) {
      await _eventStream.close();
      return event;
    } else {
      return event;
    }
  }

  /// The duration of this call.  This duration will represent the elasped time, until the call
  /// completes.
  Duration get duration {
    return _duration ?? sinceNow(startTime);
  }

  /// Subscribes to all events for this call
  Stream<PhoneCallEvent> get eventStream {
    return _isComplete ? Stream.empty() : _getOrCreateEventController().stream;
  }

  /// Waits for the call to be complete.
  FutureOr<PhoneCall> get done {
    if (_isComplete) return this;
    return _getOrCreateEventController().done.then((_) {
      _log.info("Finished call.  Status $status");
      return this;
    });
  }

  /// Sometimes, the call events get mixed up or lost, and we end up with an orphaned call.  A call is orphaned if:
  /// - It's in a dialing state for more than 30 seconds
  /// - It's in an active state for more than 8 hours
  bool get isExpired {
    if (status == PhoneCallStatus.dialing && sinceNow(startTime).inSeconds > 30)
      return true;
    if (status == PhoneCallStatus.connected && sinceNow(startTime).inHours > 8)
      return true;
    return false;
  }

  /// Whether or not this call is expired.  See [isExpired]
  bool get isNotExpired => !isExpired;

  /// Whether this call can be linked to the provided event.  This check is fairly loose, it makes sure that
  /// the values aren't for two disparate ids, phone numbers, and that the status is a subsequent status
  bool canBeLinked(RawPhoneEvent event) {
    if (event.phoneNumber != null &&
        this.phoneNumber != null &&
        event.phoneNumber != this.phoneNumber) return false;
    if (this.callId != null && this.callId != event.id) return false;
    if (isNotBefore(status, event.type)) return false;

    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhoneCall && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  /// Logs a phone call status, and fires the appropriate events
  PhoneCallEvent recordStatus(PhoneCallStatus status) {
    this.status = status;
    final event = PhoneCallEvent(this, status);
    this.events.add(event);
    if (_eventStream?.isClosed == true) {
      throw "Illegal state for call ${truncate(id, 12)}:  Received status event after closing stream";
    }
    _eventStream?.add(event);
    return event;
  }

  StreamController<PhoneCallEvent> _getOrCreateEventController() =>
      _eventStream ??= StreamController<PhoneCallEvent>.broadcast();
}

enum RawEventType { inbound, outbound, connected, disconnected }
enum PhoneCallStatus {
  ringing,
  dialing,
  cancelled,
  error,
  connecting,
  connected,
  timedOut,
  disconnected
}
enum PhoneCallPlacement { inbound, outbound }

const Map<RawEventType, Set<PhoneCallStatus>> priorStatuses = {
  RawEventType.outbound: {PhoneCallStatus.dialing},
  RawEventType.connected: {
    PhoneCallStatus.connecting,
    PhoneCallStatus.ringing,
    PhoneCallStatus.dialing
  },
  RawEventType.inbound: {},
  RawEventType.disconnected: {
    PhoneCallStatus.connecting,
    PhoneCallStatus.ringing,
    PhoneCallStatus.dialing,
    PhoneCallStatus.connected
  },
};

bool isNotBefore(PhoneCallStatus status, RawEventType type) =>
    !isBefore(status, type);

bool isBefore(PhoneCallStatus status, RawEventType type) {
  return priorStatuses[type]?.contains(status) == true;
}
