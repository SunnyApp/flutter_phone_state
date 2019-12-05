#import "FlutterPhoneStatePlugin.h"
#import <flutter_phone_state/flutter_phone_state-Swift.h>

@implementation FlutterPhoneStatePlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftFlutterPhoneStatePlugin registerWithRegistrar:registrar];
}
@end
