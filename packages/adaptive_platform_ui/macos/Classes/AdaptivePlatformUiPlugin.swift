import AppKit
import FlutterMacOS

public final class AdaptivePlatformUiPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "nipaplay/native_media_controls", binaryMessenger: registrar.messenger)
        channel.setMethodCallHandler { call, result in
            guard call.method == "supportsGlass" else { result(FlutterMethodNotImplemented); return }
            if #available(macOS 26.0, *) { result(true) } else { result(false) }
        }
        registrar.register(MediaControlFactory(registrar.messenger), withId: "nipaplay/native_media_control")
    }
}

private final class MediaControlFactory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger
    init(_ messenger: FlutterBinaryMessenger) { self.messenger = messenger }
    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? { FlutterStandardMessageCodec.sharedInstance() }
    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        MediaControlView(viewId, messenger, args as? [String: Any] ?? [:])
    }
}

private final class MediaControlView: NSView {
    let button = NSButton(title: "", target: nil, action: nil)
    let channel: FlutterMethodChannel
    var entries: [[String: Any]]?

    init(_ id: Int64, _ messenger: FlutterBinaryMessenger, _ args: [String: Any]) {
        channel = FlutterMethodChannel(name: "nipaplay/native_media_control_\(id)", binaryMessenger: messenger)
        super.init(frame: .zero)
        button.target = self
        button.action = #selector(pressed)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        update(args)
        channel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "update":
                if let args = call.arguments as? [String: Any] { self?.update(args) }
                result(nil)
            case "activate":
                if let self, self.button.isEnabled { self.button.performClick(nil) }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
    // AppKitView input is not forwarded by the pinned Flutter SDK. Let the
    // Flutter gesture/focus layer own input, avoiding duplicate native clicks.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { channel.setMethodCallHandler(nil) }

    func update(_ args: [String: Any]) {
        let label = args["label"] as? String ?? ""
        let detail = args["detail"] as? String ?? ""
        button.isEnabled = args["enabled"] as? Bool ?? false
        entries = args["items"] as? [[String: Any]]
        button.image = NSImage(systemSymbolName: args["symbol"] as? String ?? "", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.setAccessibilityLabel(label)
        button.setAccessibilityHelp(detail)
        if #available(macOS 26.0, *) {
            button.bezelStyle = .glass
            button.borderShape = .capsule
            let primary = args["primary"] as? Bool ?? false
            button.tintProminence = primary ? .primary : .none
            if primary, let argb = args["color"] as? NSNumber {
                let value = argb.uint32Value
                button.bezelColor = NSColor(red: CGFloat((value >> 16) & 255) / 255,
                    green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255,
                    alpha: CGFloat((value >> 24) & 255) / 255)
            } else { button.bezelColor = nil }
            button.contentTintColor = nil
        }
        let alignment = NSMutableParagraphStyle()
        alignment.alignment = .center
        alignment.lineBreakMode = .byTruncatingTail
        let primary = args["primary"] as? Bool ?? false
        let title = NSMutableAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: primary ? NSColor.white : NSColor.labelColor, .paragraphStyle: alignment,
        ])
        if !detail.isEmpty {
            title.append(NSAttributedString(string: "\n" + detail, attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: primary ? NSColor.white.withAlphaComponent(0.78) : NSColor.secondaryLabelColor, .paragraphStyle: alignment,
            ]))
        }
        button.attributedTitle = title
    }

    @objc func pressed() {
        guard let entries else { channel.invokeMethod("pressed", arguments: nil); return }
        let menu = NSMenu()
        for (index, entry) in entries.enumerated() {
            let item = NSMenuItem(title: entry["label"] as? String ?? "", action: #selector(selected(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.isEnabled = entry["enabled"] as? Bool ?? true
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }
    @objc func selected(_ item: NSMenuItem) { channel.invokeMethod("selected", arguments: item.tag) }
}
