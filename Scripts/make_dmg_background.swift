import AppKit
// Renders the DMG window background (660×400 pt) at a given scale. Usage: swift make_dmg_background.swift out.png <scale>
let scale = CGFloat(Double(CommandLine.arguments[2]) ?? 1)
let W: CGFloat = 660, H: CGFloat = 400
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let r = NSRect(x: 0, y: 0, width: W, height: H)
NSGradient(colors: [NSColor(srgbRed: 0.97, green: 0.97, blue: 1.0, alpha: 1), NSColor(srgbRed: 0.90, green: 0.91, blue: 0.97, alpha: 1)])!
    .draw(in: r, angle: -90)
// soft glow
let c = NSPoint(x: W / 2, y: H / 2 + 10)
NSGradient(colors: [NSColor(srgbRed: 0.42, green: 0.39, blue: 1, alpha: 0.10), .clear])!
    .draw(fromCenter: c, radius: 0, toCenter: c, radius: 300, options: [])
// arrow between the two icons (icons sit at x=170 and x=490, y=200 from top)
let y = H - 200
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 262, y: y))
arrow.curve(to: NSPoint(x: 392, y: y), controlPoint1: NSPoint(x: 300, y: y + 26), controlPoint2: NSPoint(x: 354, y: y + 26))
arrow.lineWidth = 5
arrow.lineCapStyle = .round
NSColor(srgbRed: 0.42, green: 0.39, blue: 1, alpha: 0.6).setStroke()
let dash: [CGFloat] = [2, 12]
arrow.setLineDash(dash, count: 2, phase: 0)
arrow.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 404, y: y - 2))
head.line(to: NSPoint(x: 384, y: y + 14))
head.line(to: NSPoint(x: 386, y: y - 12))
head.close()
NSColor(srgbRed: 0.42, green: 0.39, blue: 1, alpha: 0.8).setFill()
head.fill()
// caption
let p = NSMutableParagraphStyle(); p.alignment = .center
let title = NSAttributedString(string: "Drag Rondo to Applications", attributes: [
    .font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: NSColor(srgbRed: 0.10, green: 0.11, blue: 0.2, alpha: 0.9), .paragraphStyle: p])
title.draw(in: NSRect(x: 0, y: 70, width: W, height: 24))
let sub = NSAttributedString(string: "Trascina · Arrastra · Glissez · Ziehen · Arraste", attributes: [
    .font: NSFont.systemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor(srgbRed: 0.10, green: 0.11, blue: 0.2, alpha: 0.45), .paragraphStyle: p])
sub.draw(in: NSRect(x: 0, y: 48, width: W, height: 18))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
