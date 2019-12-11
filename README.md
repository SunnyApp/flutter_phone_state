# Flutter Phone State Plugin

[![pub package](https://img.shields.io/pub/v/flutter_phone_state.svg)](https://pub.dartlang.org/packages/flutter_phone_state)
[![Coverage Status](https://coveralls.io/repos/github/SunnyApp/flutter_phone_state/badge.svg?branch=master)](https://coveralls.io/github/SunnyApp/flutter_phone_state?branch=master)


A Flutter plugin that makes it easier to make and track phone calls.  The core features are:

1.  Initiate a phone call in 1 line of code
2.  `await` any in-flight phone call
3.  Watch all phone-related events for a single call, or all calls
4.  Track duration of calls, errors, and cancellations

## Getting Started

Install the plugin:

```yaml
flutter_phone_state: ^0.5.7
```

## Before you start

Both Android and iOS put restrictions on accessing phone call data. This plugin makes a 
best-effort attempt to track the complete lifecycle of a phone call, but it's not perfect and has its limitations.  Read the 
`Limitations` section below for more info.

## Initiate a call

It's recommended that you initiate calls from your app when possible.  This gives you the 
best chance at tracking the call.
```dart
// note: this plugin will remove all non-numeric characters from the phone number
final phoneCall = FlutterPhoneState.makePhoneCall("480-555-1234"); 
```

A `PhoneCall` object is the source of truth for the call

```dart
showCallInfo(PhoneCall phoneCall) {
    print(phoneCall.status); // ringing, dialing, cancelled, error, connecting, connected, timedOut, disconnected 
    print(phoneCall.isComplete); // Whether the call is complete
    print(phoneCall.events); // A list of call events related to this specific call
}
```

You can read the `PhoneCall.events` as a stream, and when the call is completed, the plugin will 
close the stream gracefully.  The plugin watches all in-flight calls, and will force any 
call to timeout eventually.
```dart
watchEvents(PhoneCall phoneCall) {
  phoneCall.eventStream.forEach((PhoneCallEvent event) {
    print("Event $event");
  });
  print("Call is complete");
}
```

Alternatively, you can just wait for the call to complete
```dart
waitForCompletion(PhoneCall phoneCall) async {
  await phoneCall.done;
  print("Call is completed");
}
```

## Accessing in-flight calls

In-flight calls can be accessed like this:
```dart
final activeCalls = FutterPhoneState.activeCalls;
```
Note that `activeCalls` is an immutable copy of the calls at the moment you called `activeCalls`.  It 
won't update automatically.

## Watching all events

Instead of focusing on a single call, you can watch all the events. We recommend using  
`FlutterPhoneState.phoneCallEventStream` - because this `Stream` incorporates our own 
tracking logic, call timeouts, failures, etc.

```dart
_watchAllPhoneCallEvents() {
  FlutterPhoneState.phoneCallEvents.forEach((PhoneCallEvent event) {
    final phoneCall = event.call;
    print("Got an event $event");
  });
  print("That loop ^^ won't end");
}
```

If you want, you can subscribe to the raw underlying events.  Keep in mind that these events are limited.

```dart
_watchAllRawEvents() {
  FlutterPhoneState.rawPhoneEvent.forEach((RawPhoneEvent event) {
    final phoneCall = event.call;
    print("Got an event $event");
  });
  print("That loop ^^ won't end");
}
```

## Limitations

### Phone Numbers

Neither platform gives us phone numbers with call events.  This is largely why we recommend initiating
the call using the plugin, so you can tie it back to the original number.

And obviously, this means that you'll never get the phone number from an inbound call.  Sorry!

### Android

Android doesn't track nested calls.  So, once the first call is active, if you receive another
call, or make another call (by putting the first on hold), the second call will not be tracked
at all.  

Also, Android doesn't provide a unique call identifier, so any call events that occur can't be linked 
together with a platform-assigned id.

## How does it work?

1.  This plugin registers to `AppLifecycleState` events, and uses those events to determine when 
an outbound call has been placed vs cancelled.
2.  When possible, the plugin links phone lifecycle events together by the platform-assigned 
call identifier. (this works on iOS)
3.  The plugin checks the actual lifecycle states - for example, if one call is `connected` and 
the plugin gets a `dialing` event, it's clear that the `dialing` event must be for a new/different call, and
therefore begins tracking it as a new call.  
