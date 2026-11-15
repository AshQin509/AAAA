import AppKit

final class PasteRecorder:NSResponder {
    var pastes=0
    @objc func paste(_ sender:Any?) { pastes += 1 }
}
@main struct WindowInteractionTests {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var failures=0
        func check(_ condition:Bool,_ message:String) { if !condition { print("FAIL: "+message); failures += 1 } }
        let parent=NSView(frame:NSRect(x:0,y:0,width:600,height:800))
        let header=TitlebarView(frame:NSRect(x:30,y:70,width:440,height:76))
        parent.addSubview(header); header.layoutSubtreeIfNeeded()
        check(header.acceptsFirstMouse(for:nil),"Header must start dragging on the first inactive-window click")
        check(header.closeButton.acceptsFirstMouse(for:nil),"Close must accept the first inactive-window click")
        let closePoint=NSPoint(x:header.frame.minX+header.closeButton.frame.midX,y:header.frame.minY+header.closeButton.frame.midY)
        check(header.hitTest(closePoint) === header.closeButton,"Close button must not be intercepted by the drag surface")
        check(header.hitTest(NSPoint(x:header.frame.minX+90,y:header.frame.minY+30)) === header,"Title text must be a drag surface")
        check(header.hitTest(NSPoint(x:header.frame.minX+300,y:header.frame.minY+30)) === header,"Blank header must be a drag surface")
        check(header.hitTest(NSPoint(x:header.frame.minX-1,y:header.frame.minY)) == nil,"Header must not intercept clicks outside its frame")
        var closes=0; header.onClose={ closes += 1 }
        for _ in 0..<10 { header.closeButton.performClick(nil) }
        check(closes==10,"Ten native close-button actions must produce ten callbacks")
        header.onClose={ closes += 100 }; header.closeButton.performClick(nil)
        check(closes==110,"Updated close action must replace the prior callback")
        let recorder=PasteRecorder()
        func event(_ flags:NSEvent.ModifierFlags,_ chars:String) -> NSEvent { NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:chars,charactersIgnoringModifiers:chars,isARepeat:false,keyCode:9)! }
        check(EditingShortcuts.handle(event(.command,"v"),responder:recorder),"Cmd-V must reach the field editor")
        check(recorder.pastes==1,"Paste must be dispatched exactly once")
        check(!EditingShortcuts.handle(event([],"v"),responder:recorder),"Typing v without Command must not paste")
        check(!EditingShortcuts.handle(event([.command,.option],"v"),responder:recorder),"Other modifier combinations must retain their meaning")
        print("Native window chrome: 12 assertions, \(failures) failures (no onscreen window or input injection)")
        exit(failures==0 ? 0:1)
    }
}
