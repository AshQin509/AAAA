import AppKit
let image=NSImage(contentsOfFile:CommandLine.arguments[1])!
let dir=URL(fileURLWithPath:CommandLine.arguments[2])
for base in [16,32,128,256,512] {
 for scale in [1,2] {
  let size=base*scale
  let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
  NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
  let height=CGFloat(size)*image.size.height/image.size.width
  image.draw(in:NSRect(x:0,y:(CGFloat(size)-height)/2,width:CGFloat(size),height:height))
  NSGraphicsContext.restoreGraphicsState()
  try rep.representation(using:.png,properties:[:])!.write(to:dir.appendingPathComponent("icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"))
 }
}
