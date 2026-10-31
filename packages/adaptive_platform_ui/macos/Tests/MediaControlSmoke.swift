// Compiled together with the plugin source by tool/test_native_media_controls_macos.sh.
final class TestMessenger: NSObject, FlutterBinaryMessenger {
    var handlers: [String: FlutterBinaryMessageHandler] = [:]
    var events: [FlutterMethodCall] = []
    let codec = FlutterStandardMethodCodec.sharedInstance()
    func send(onChannel channel: String, message: Data?) {
        if let message { events.append(codec.decodeMethodCall(message)) }
    }
    func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
        send(onChannel: channel, message: message)
        callback?(nil)
    }
    func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
        handlers[channel] = handler
        return 1
    }
    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let messenger = TestMessenger()
let accent = NSNumber(value: UInt32(0xFFFF7274))
private let control = MediaControlView(42, messenger, ["label": "观看", "symbol": "play.fill", "primary": true, "color": accent, "enabled": true])
if #available(macOS 26.0, *) {
    assert(control.button.tintProminence == .primary)
    let color = control.button.bezelColor!.usingColorSpace(.deviceRGB)!
    assert(abs(color.redComponent - 1) < 0.001)
    assert(abs(color.greenComponent - 114.0/255) < 0.001)
}
assert(control.hitTest(NSPoint(x: 1, y: 1)) == nil)
let activate = messenger.codec.encode(FlutterMethodCall(methodName: "activate", arguments: nil))
messenger.handlers["nipaplay/native_media_control_42"]!(activate) { _ in }
assert(messenger.events.map(\.method) == ["pressed"])
for title in ["返回", "评论", "更多", "选择剧集"] {
    control.update(["label": title, "primary": false, "enabled": true])
    if #available(macOS 26.0, *) { assert(control.button.tintProminence == .none) }
    assert(control.button.bezelColor == nil)
}
control.update(["label": "观看", "enabled": false])
messenger.handlers["nipaplay/native_media_control_42"]!(activate) { _ in }
assert(messenger.events.count == 1)
control.update(["label": "更多", "enabled": true, "items": [["label": "修改背景图", "enabled": true]]])
assert(control.entries?.count == 1)
let selectedItem = NSMenuItem(title: "修改背景图", action: nil, keyEquivalent: "")
selectedItem.tag = 0
control.selected(selectedItem)
assert(messenger.events.last!.method == "selected")
assert(messenger.events.last!.arguments as? Int == 0)
print("Native control checks passed: accent, neutral tint, activation, disabled state, native menu callback")
