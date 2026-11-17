import AppKit
// Deterministic vector drawing matching Assets/AppIcon.svg. No generated bitmap input.
func color(_ rgb: Int) -> NSColor { NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1) }
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let transform = AffineTransform(translationByX: 0, byY: 1024)
var flip = transform; flip.scale(x: 1, y: -1)
(flip as NSAffineTransform).concat()
color(0xEDE9DF).setFill()
NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 184, yRadius: 184).fill()
let page = NSBezierPath()
page.move(to: NSPoint(x:304,y:210)); page.line(to:NSPoint(x:626,y:210)); page.line(to:NSPoint(x:754,y:338)); page.line(to:NSPoint(x:754,y:770))
page.curve(to:NSPoint(x:720,y:804),controlPoint1:NSPoint(x:754,y:792),controlPoint2:NSPoint(x:742,y:804))
page.line(to:NSPoint(x:304,y:804)); page.curve(to:NSPoint(x:270,y:770),controlPoint1:NSPoint(x:282,y:804),controlPoint2:NSPoint(x:270,y:792))
page.line(to:NSPoint(x:270,y:244)); page.curve(to:NSPoint(x:304,y:210),controlPoint1:NSPoint(x:270,y:222),controlPoint2:NSPoint(x:282,y:210)); page.close()
color(0xFAF8F2).setFill(); page.fill()
color(0x30373A).setStroke(); page.lineWidth=22; page.lineJoinStyle = .round; page.stroke()
let fold=NSBezierPath(); fold.move(to:NSPoint(x:626,y:210)); fold.line(to:NSPoint(x:626,y:314)); fold.curve(to:NSPoint(x:650,y:338),controlPoint1:NSPoint(x:626,y:330),controlPoint2:NSPoint(x:634,y:338)); fold.line(to:NSPoint(x:754,y:338)); fold.close(); color(0xC56A45).setFill(); fold.fill()
func polygon(_ points: [(Int,Int)], _ rgb: Int) { let path=NSBezierPath(); path.move(to:NSPoint(x:points[0].0,y:points[0].1)); for p in points.dropFirst() { path.line(to:NSPoint(x:p.0,y:p.1)) }; path.close(); color(rgb).setFill(); path.fill() }
polygon([(330,578),(330,426),(376,426),(424,495),(472,426),(518,426),(518,578),(472,578),(472,504),(424,570),(376,504),(376,578)],0x30373A)
polygon([(608,426),(654,426),(654,512),(690,512),(631,578),(572,512),(608,512)],0x30373A)
let lines=NSBezierPath(); lines.move(to:NSPoint(x:340,y:656)); lines.line(to:NSPoint(x:680,y:656)); lines.move(to:NSPoint(x:340,y:710)); lines.line(to:NSPoint(x:570,y:710)); lines.lineWidth=18; lines.lineCapStyle = .round; color(0xCBC8BF).setStroke(); lines.stroke()
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
