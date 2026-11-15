import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import CodeCoachCore
#endif

@main struct CodeCoachApp {
    @MainActor static func main() {
        let app=NSApplication.shared
        let delegate=AppDelegate(); app.delegate=delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var collapse: (() -> Void)?
    override func cancelOperation(_ sender:Any?) { collapse?() }
    override func performKeyEquivalent(with event:NSEvent) -> Bool {
        if EditingShortcuts.handle(event,responder:firstResponder) { return true }
        return super.performKeyEquivalent(with:event)
    }
}
final class CompactHost: FirstClickHostingView<CompactCoach> {
    var clicked: (() -> Void)?
    var endedDrag: (() -> Void)?
    private var gesture=PointerGesture()
    private var startOrigin=NSPoint.zero
    private func screenPoint(_ event:NSEvent) -> NSPoint { window?.convertPoint(toScreen:event.locationInWindow) ?? event.locationInWindow }
    override func mouseDown(with event:NSEvent) {
        guard let window, event.clickCount == 1 else { return }
        startOrigin=window.frame.origin
        gesture.begin(at:screenPoint(event))
    }
    override func mouseDragged(with event:NSEvent) {
        let point=screenPoint(event); gesture.update(at:point)
        guard gesture.dragging, let start=gesture.start else { return }
        window?.setFrameOrigin(NSPoint(x:startOrigin.x+point.x-start.x,y:startOrigin.y+point.y-start.y))
    }
    override func mouseUp(with event:NSEvent) {
        switch gesture.end(at:screenPoint(event)) {
        case .click: if bounds.contains(convert(event.locationInWindow,from:nil)) { clicked?() }
        case .drag: endedDrag?()
        case .none: break
        }
    }
    override func hitTest(_ point:NSPoint) -> NSView? { bounds.contains(convert(point,from:superview)) ? self : nil }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "Open Don't Crash; drag to move" }
    override func accessibilityPerformPress() -> Bool { clicked?(); return true }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model=AppModel()
    private var panel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private var expanded=false
    private var expandedFrameAtOpen:NSRect?
    private var positionSave:DispatchWorkItem?
    private var hasPresented=false
    func applicationDidFinishLaunching(_ notification:Notification) {
        panel=FloatingPanel(contentRect:NSRect(x:100,y:100,width:44,height:44),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isFloatingPanel=true; panel.level = .floating; panel.hidesOnDeactivate=false
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.isOpaque=false; panel.backgroundColor = .clear; panel.hasShadow=true
        panel.delegate=self; panel.collapse={ [weak self] in self?.show(expanded:false) }
        let stored=UserDefaults.standard.array(forKey:"buttonOrigin") as? [Double]
        let screen=NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1200,height:800)
        panel.setFrameOrigin(stored.flatMap { $0.count == 2 ? NSPoint(x:$0[0],y:$0[1]) : nil } ?? NSPoint(x:screen.maxX-126,y:screen.midY))
        show(expanded:true)
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        statusItem.button?.image=NSImage(systemSymbolName:"curlybraces",accessibilityDescription:"Don't Crash")
        let mainMenu=NSMenu()
        let appItem=NSMenuItem(); let appMenu=NSMenu()
        let quitItem=NSMenuItem(title:"Quit Don't Crash",action:#selector(quit),keyEquivalent:"q"); quitItem.target=self
        appMenu.addItem(quitItem); appItem.submenu=appMenu; mainMenu.addItem(appItem)
        let editItem=NSMenuItem();editItem.title="Edit"
        let editMenu=NSMenu(title:"Edit")
        for (title,action,key) in [("Undo","undo:","z"),("Cut","cut:","x"),("Copy","copy:","c"),("Paste","paste:","v"),("Select All","selectAll:","a")] {
            editMenu.addItem(withTitle:title,action:NSSelectorFromString(action),keyEquivalent:key)
        }
        editItem.submenu=editMenu;mainMenu.addItem(editItem)
        NSApplication.shared.mainMenu=mainMenu
        let menu=NSMenu()
        menu.addItem(withTitle:"Show Don't Crash",action:#selector(reveal),keyEquivalent:"")
        menu.addItem(withTitle:"Start / Pause",action:#selector(toggleMonitoring),keyEquivalent:"")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle:"Quit Don't Crash",action:#selector(quit),keyEquivalent:"q")
        for item in menu.items { item.target=self }; statusItem.menu=menu
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(screenChanged),name:NSWorkspace.activeSpaceDidChangeNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(screenChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
    }
    @objc func reveal() { show(expanded:true) }
    @objc func toggleMonitoring() { model.running ? model.pause() : model.start() }
    @objc func quit() { model.pause(); model.cancelQuiz(); NSApplication.shared.terminate(nil) }
    @objc func screenChanged() { clamp(); panel.orderFrontRegardless() }
    func applicationWillTerminate(_ notification:Notification) { model.pause(); model.cancelQuiz() }
    func windowDidMove(_ notification:Notification) {
        positionSave?.cancel()
        let item=DispatchWorkItem { [weak self] in
            guard let self, !self.expanded else { return }
            self.savePosition()
        }
        positionSave=item; DispatchQueue.main.asyncAfter(deadline:.now()+0.2,execute:item)
    }
    private func savePosition() { UserDefaults.standard.set([panel.frame.minX,panel.frame.minY],forKey:"buttonOrigin") }
    func windowDidEndLiveResize(_ notification:Notification) { clamp() }
    private var compactOrigin: NSPoint?
    func show(expanded:Bool) {
        if hasPresented && expanded == self.expanded { panel.orderFrontRegardless(); return }
        hasPresented=true
        let wasExpanded=self.expanded
        if expanded && !wasExpanded { compactOrigin=panel.frame.origin }
        self.expanded=expanded
        let size=expanded ? NSSize(width:620,height:720):NSSize(width:44,height:44)
        let old=panel.frame
        let panelMoved = wasExpanded && expandedFrameAtOpen.map { hypot(old.minX-$0.minX,old.minY-$0.minY)>1 } == true
        let origin: NSPoint
        if !expanded && panelMoved { origin=NSPoint(x:old.maxX-size.width,y:old.maxY-size.height) }
        else { origin = !expanded ? (compactOrigin ?? old.origin) : NSPoint(x:old.maxX-size.width,y:old.maxY-size.height) }
        panel.setFrame(NSRect(origin:origin,size:size),display:true)
        if expanded { panel.contentView=FirstClickHostingView(rootView:CoachPanel(model:model,collapse:{ [weak self] in self?.show(expanded:false) })) }
        else { let view=CompactHost(rootView:CompactCoach(model:model)); view.clicked={ [weak self] in self?.show(expanded:true) }; view.endedDrag={ [weak self] in self?.clamp(); self?.savePosition() }; panel.contentView=view }
        clamp(); panel.orderFrontRegardless()
        if expanded { expandedFrameAtOpen=panel.frame; panel.makeKey() }
        else { compactOrigin=panel.frame.origin; savePosition() }
    }
    func clamp() {
        let screens=NSScreen.screens
        let screen=screens.max { a,b in area(a.visibleFrame.intersection(panel.frame)) < area(b.visibleFrame.intersection(panel.frame)) } ?? NSScreen.main
        guard let visible=screen?.visibleFrame else { return }
        var frame=panel.frame
        frame.origin.x=min(max(frame.minX,visible.minX+8),max(visible.minX+8,visible.maxX-frame.width-8))
        frame.origin.y=min(max(frame.minY,visible.minY+8),max(visible.minY+8,visible.maxY-frame.height-8))
        if frame != panel.frame { panel.setFrame(frame,display:true) }
    }
    private func area(_ rect:NSRect) -> CGFloat { rect.isNull ? 0 : rect.width*rect.height }
}
