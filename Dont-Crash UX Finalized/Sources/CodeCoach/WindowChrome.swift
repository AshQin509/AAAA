import AppKit
import SwiftUI

/// Click-through controls must accept the first click even when another app is active.
class FirstClickHostingView<Content:View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class ClosePanelButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct PanelTitlebar: NSViewRepresentable {
    let collapse: () -> Void
    func makeNSView(context:Context) -> TitlebarView {
        let view=TitlebarView(); view.onClose=collapse; return view
    }
    func updateNSView(_ view:TitlebarView,context:Context) { view.onClose=collapse }
}

/// A native titlebar with one isolated button; every other point is a drag surface.
final class TitlebarView: NSView {
    let closeButton=ClosePanelButton()
    var onClose:(() -> Void)?
    private let title=NSTextField(labelWithString:"Don't Crash")
    private let subtitle=NSTextField(labelWithString:"Think clearly. Build confidently.")
    private let icon=NSImageView()
    override var isFlipped:Bool { true }
    override var intrinsicContentSize:NSSize { NSSize(width:NSView.noIntrinsicMetric,height:76) }
    override init(frame:NSRect) {
        super.init(frame:frame)
        appearance=NSAppearance(named:.aqua)
        title.font = .systemFont(ofSize:20,weight:.semibold); title.textColor = .systemBlue
        subtitle.font = .monospacedSystemFont(ofSize:12,weight:.medium); subtitle.textColor = .secondaryLabelColor
        icon.image=CompanionArtwork.image
        icon.imageScaling = .scaleProportionallyUpOrDown
        closeButton.image=NSImage(systemSymbolName:"xmark",accessibilityDescription:"Close panel")
        closeButton.contentTintColor = .labelColor; closeButton.isBordered=false; closeButton.bezelStyle = .circular
        closeButton.wantsLayer=true; closeButton.layer?.cornerRadius=16
        closeButton.layer?.backgroundColor=NSColor.systemBlue.withAlphaComponent(0.08).cgColor
        closeButton.setAccessibilityLabel("Close panel"); closeButton.toolTip="Close panel and pause monitoring"
        closeButton.target=self; closeButton.action=#selector(closePressed)
        [icon,title,subtitle,closeButton].forEach(addSubview)
        toolTip="Drag the title bar to move the panel"
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is unsupported") }
    override func layout() {
        super.layout()
        icon.frame=NSRect(x:20,y:24,width:24,height:28)
        title.frame=NSRect(x:56,y:15,width:max(0,bounds.width-126),height:26)
        subtitle.frame=NSRect(x:56,y:43,width:max(0,bounds.width-126),height:14)
        closeButton.frame=NSRect(x:bounds.width-52,y:22,width:32,height:32)
    }
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
    override func hitTest(_ point:NSPoint) -> NSView? {
        let local=convert(point,from:superview)
        guard !isHidden, bounds.contains(local) else { return nil }
        if closeButton.frame.contains(local) { return closeButton }
        return self
    }
    override func mouseDown(with event:NSEvent) { window?.performDrag(with:event) }
    @objc private func closePressed() { onClose?() }
}

/// Nonactivating panels still need to route standard text shortcuts to their field editor.
enum EditingShortcuts {
    static func handle(_ event:NSEvent,responder:NSResponder?) -> Bool {
        let flags=event.modifierFlags.intersection([.command,.shift,.option,.control])
        guard flags == [.command] || flags == [.command,.shift] else { return false }
        let key=event.charactersIgnoringModifiers?.lowercased() ?? ""
        let name:String
        switch (key,flags.contains(.shift)) {
        case ("v",false): name="paste:"
        case ("c",false): name="copy:"
        case ("x",false): name="cut:"
        case ("a",false): name="selectAll:"
        case ("z",false): name="undo:"
        case ("z",true): name="redo:"
        default: return false
        }
        return responder?.tryToPerform(NSSelectorFromString(name),with:nil) ?? false
    }
}

// Shared image loader for Xcode, standalone builds, and Swift Package Manager.
enum CompanionArtwork {
    static var image: NSImage {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return bundle.url(forResource:"Companion",withExtension:"png").flatMap { NSImage(contentsOf:$0) } ?? NSImage(systemSymbolName:"face.smiling",accessibilityDescription:nil)!
    }
}
