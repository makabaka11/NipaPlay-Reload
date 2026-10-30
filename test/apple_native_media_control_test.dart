import 'package:adaptive_platform_ui/adaptive_platform_ui.dart' as native;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/apple_native_media_control.dart';
import 'package:nipaplay/themes/nipaplay/widgets/adaptive_media_detail_action.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nipaplay/native_media_controls');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    native.PlatformInfo.setPlatformOverride(native.PlatformOverride.macos);
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await AppleNativeMediaControl.initialize();
    native.PlatformInfo.clearPlatformOverride();
  });

  test('macOS uses the native capability answer rather than the iOS gate',
      () async {
    for (final supported in [true, false]) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'supportsGlass');
        return supported;
      });
      await AppleNativeMediaControl.initialize();
      expect(AppleNativeMediaControl.supported, supported);
      expect(
          AdaptiveMediaDetailActionButton.supportsNativeLiquidGlass, supported);
    }
  });

  test('missing or failing native bridge clears support and falls back',
      () async {
    messenger.setMockMethodCallHandler(channel, (_) async => true);
    await AppleNativeMediaControl.initialize();
    expect(AppleNativeMediaControl.supported, isTrue);
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    await AppleNativeMediaControl.initialize();
    expect(AdaptiveMediaDetailActionButton.supportsNativeLiquidGlass, isFalse);
    messenger.setMockMethodCallHandler(channel, null);
    await AppleNativeMediaControl.initialize();
    expect(AppleNativeMediaControl.supported, isFalse);
  });
}
