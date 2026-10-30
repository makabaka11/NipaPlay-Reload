import 'package:adaptive_platform_ui/adaptive_platform_ui.dart' as native;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/utils/platform_identity.dart';
import 'package:nipaplay/utils/platform_utils.dart';

/// macOS and tvOS use a dedicated bridge; iOS keeps its existing bridge.
class AppleNativeMediaControl extends StatefulWidget {
  const AppleNativeMediaControl({
    super.key,
    required this.label,
    required this.symbol,
    this.detail,
    this.primary = false,
    this.color,
    this.onPressed,
    this.items,
    this.onSelected,
  });

  static const _capabilities = MethodChannel('nipaplay/native_media_controls');
  static bool _supported = false;
  static bool get supported => _supported;

  static Future<void> initialize() async {
    _supported = false;
    if (kIsWeb || !(native.PlatformInfo.isMacOS || isTvOS)) return;
    try {
      _supported =
          await _capabilities.invokeMethod<bool>('supportsGlass') ?? false;
    } on MissingPluginException {
      // Older/unregistered native builds retain the Flutter controls.
    } on PlatformException {
      // A failed capability query must never enable an unavailable view.
    }
  }

  final String label;
  final String symbol;
  final String? detail;
  final bool primary;
  final Color? color;
  final VoidCallback? onPressed;
  final List<Map<String, Object?>>? items;
  final ValueChanged<int>? onSelected;

  @override
  State<AppleNativeMediaControl> createState() =>
      _AppleNativeMediaControlState();
}

class _AppleNativeMediaControlState extends State<AppleNativeMediaControl> {
  MethodChannel? _channel;

  Map<String, Object?> get _parameters => {
        'label': widget.label,
        'symbol': widget.symbol,
        'detail': widget.detail,
        'primary': widget.primary,
        'color': widget.color?.toARGB32(),
        'enabled': widget.items != null || widget.onPressed != null,
        'items': widget.items,
      };

  void _onCreated(int id) {
    _channel?.setMethodCallHandler(null);
    _channel = MethodChannel('nipaplay/native_media_control_$id');
    _channel!.setMethodCallHandler((call) async {
      if (call.method == 'pressed') widget.onPressed?.call();
      if (call.method == 'selected') {
        final index = call.arguments;
        if (index is int && index >= 0 && index < (widget.items?.length ?? 0)) {
          widget.onSelected?.call(index);
        }
      }
    });
    _update();
  }

  @override
  void didUpdateWidget(covariant AppleNativeMediaControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  Future<void> _update() async {
    try {
      await _channel?.invokeMethod<void>('update', _parameters);
    } on MissingPluginException {
      // The platform view may have been removed by a route transition.
    } on PlatformException catch (error) {
      debugPrint('Native media control update failed: $error');
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Native views must not remain above a Flutter dialog or pushed route.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      return const SizedBox(height: 44);
    }
    const codec = StandardMessageCodec();
    return SizedBox(
      height: 44,
      child: Platform.isMacOS
          ? AppKitView(
              viewType: 'nipaplay/native_media_control',
              creationParams: _parameters,
              creationParamsCodec: codec,
              onPlatformViewCreated: _onCreated,
            )
          : UiKitView(
              viewType: 'nipaplay/native_media_control',
              creationParams: _parameters,
              creationParamsCodec: codec,
              onPlatformViewCreated: _onCreated,
            ),
    );
  }
}
