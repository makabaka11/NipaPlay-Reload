import 'package:adaptive_platform_ui/adaptive_platform_ui.dart' as native;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
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

  testWidgets('macOS click and keyboard activation reach Swift once each',
      (tester) async {
    final channels = <MethodChannel>[];
    final commands = <String>[];
    var pressed = 0;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final args = call.arguments as Map;
        final control =
            MethodChannel('nipaplay/native_media_control_${args['id']}');
        channels.add(control);
        messenger.setMockMethodCallHandler(control, (call) async {
          commands.add(call.method);
          if (call.method == 'activate') {
            await messenger.handlePlatformMessage(
                control.name,
                const StandardMethodCodec()
                    .encodeMethodCall(const MethodCall('pressed')),
                (_) {});
          }
          return null;
        });
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      for (final channel in channels) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: GestureDetector(
      onTap: () => fail('parent must not consume native button clicks'),
      child: SizedBox(
          width: 120,
          child: AppleNativeMediaControl(
            label: '评论',
            symbol: 'bubble.right',
            onPressed: () => pressed++,
          )),
    ))));
    await tester.pumpAndSettle();
    final button = find.byType(AppleNativeMediaControl);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(commands.where((value) => value == 'activate').length, 1);
    expect(pressed, 1);
    // Native views remain visual; Flutter retains pointer and keyboard routing.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(commands.where((value) => value == 'activate').length, 2);
    expect(pressed, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disabled macOS control does not dispatch activation',
      (tester) async {
    final commands = <String>[];
    MethodChannel? control;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        control = MethodChannel(
            'nipaplay/native_media_control_${(call.arguments as Map)['id']}');
        messenger.setMockMethodCallHandler(control!, (call) async {
          commands.add(call.method);
          return null;
        });
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      if (control != null) messenger.setMockMethodCallHandler(control!, null);
    });
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SizedBox(
      width: 120,
      child: AppleNativeMediaControl(label: '观看', symbol: 'play.fill'),
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppleNativeMediaControl));
    await tester.pumpAndSettle();
    expect(commands, isNot(contains('activate')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
