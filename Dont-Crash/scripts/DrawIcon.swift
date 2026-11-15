import AppKit
let dir=CommandLine.arguments[1]
for size in [16,32,64,128,256,512,1024] {
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
    let s=CGFloat(size)
    let shape=NSBezierPath(roundedRect:NSRect(x:s*0.04,y:s*0.04,width:s*0.92,height:s*0.92),xRadius:s*0.23,yRadius:s*0.23)
    NSGradient(starting:NSColor(red:0.10,green:0.20,blue:0.24,alpha:1),ending:NSColor(red:0.035,green:0.065,blue:0.10,alpha:1))!.draw(in:shape,angle:80)
    NSColor(red:0.35,green:0.85,blue:0.72,alpha:0.25).setStroke(); shape.lineWidth=s*0.012; shape.stroke()
    let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.monospacedSystemFont(ofSize:s*0.46,weight:.semibold),.foregroundColor:NSColor(red:0.4,green:0.92,blue:0.77,alpha:1)]
    let text="{ }" as NSString; let measured=text.size(withAttributes:attrs)
    text.draw(at:NSPoint(x:(s-measured.width)/2,y:(s-measured.height)/2+s*0.01),withAttributes:attrs)
    let dot=NSBezierPath(ovalIn:NSRect(x:s*0.69,y:s*0.18,width:s*0.10,height:s*0.10)); NSColor(red:0.4,green:0.92,blue:0.77,alpha:1).setFill();dot.fill()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:dir).appendingPathComponent("\(size).png"))
}
