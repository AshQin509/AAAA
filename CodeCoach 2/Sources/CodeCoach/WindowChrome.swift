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
    private let title=NSTextField(labelWithString:"Code Coach")
    private let subtitle=NSTextField(labelWithString:"JAVA · 一次弄懂一个问题")
    private let icon=NSImageView()
    override var isFlipped:Bool { true }
    override var intrinsicContentSize:NSSize { NSSize(width:NSView.noIntrinsicMetric,height:76) }
    override init(frame:NSRect) {
        super.init(frame:frame)
        appearance=NSAppearance(named:.darkAqua)
        title.font = .systemFont(ofSize:14,weight:.semibold); title.textColor = .white
        subtitle.font = .monospacedSystemFont(ofSize:9,weight:.medium); subtitle.textColor = .white.withAlphaComponent(0.5)
        icon.image=NSImage(systemSymbolName:"curlybraces",accessibilityDescription:nil)
        icon.contentTintColor=NSColor(red:0.35,green:0.85,blue:0.72,alpha:1); icon.imageScaling = .scaleProportionallyUpOrDown
        closeButton.image=NSImage(systemSymbolName:"xmark",accessibilityDescription:"关闭面板")
        closeButton.contentTintColor = .white; closeButton.isBordered=false; closeButton.bezelStyle = .circular
        closeButton.wantsLayer=true; closeButton.layer?.cornerRadius=16
        closeButton.layer?.backgroundColor=NSColor.white.withAlphaComponent(0.08).cgColor
        closeButton.setAccessibilityLabel("关闭面板"); closeButton.toolTip="关闭面板，保留悬浮图标"
        closeButton.target=self; closeButton.action=#selector(closePressed)
        [icon,title,subtitle,closeButton].forEach(addSubview)
        toolTip="拖动标题栏可移动面板"
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is unsupported") }
    override func layout() {
        super.layout()
        icon.frame=NSRect(x:20,y:24,width:24,height:28)
        title.frame=NSRect(x:56,y:21,width:max(0,bounds.width-126),height:20)
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
