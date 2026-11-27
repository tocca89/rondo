import AppKit
// Renders the 1024×1024 Rondo app icon: dark glass squircle, glowing segmented ring, frosted center with a "turn" arrow.
// Usage: swift Scripts/make_icon.swift out.png

let size: CGFloat = 1024
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
    let body = r.insetBy(dx: 100, dy: 100)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
    let c = NSPoint(x: r.midX, y: r.midY)

    // Drop shadow + base
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 36
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.set()
    NSGradient(colors: [rgb(28, 32, 58), rgb(10, 11, 22)])!.draw(in: squircle, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    // Inner glow behind the ring
    NSGradient(colors: [rgb(80, 120, 255, 0.35), rgb(80, 120, 255, 0)])!
        .draw(fromCenter: c, radius: 0, toCenter: c, radius: 380, options: [])

    // Segmented ring
    let colors: [NSColor] = [rgb(52, 225, 235), rgb(64, 156, 255), rgb(108, 99, 255), rgb(178, 92, 255), rgb(255, 90, 160), rgb(70, 220, 150)]
    for i in 0..<6 {
        let mid = 90 - CGFloat(i) * 60
        let hot = i == 0
        let outer: CGFloat = hot ? 322 : 296, inner: CGFloat = 168
        let p = NSBezierPath()
        p.appendArc(withCenter: c, radius: outer, startAngle: mid + 27, endAngle: mid - 27, clockwise: true)
        p.appendArc(withCenter: c, radius: inner, startAngle: mid - 27, endAngle: mid + 27, clockwise: false)
        p.close()
        let col = colors[i]
        let alpha: CGFloat = hot ? 1 : 0.62
        if hot {
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowBlurRadius = 70
            glow.shadowColor = col.withAlphaComponent(0.85)
            glow.set()
            col.setFill()
            p.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.saveGraphicsState()
        p.addClip()
        NSGradient(colors: [col.blended(withFraction: 0.25, of: .white)!.withAlphaComponent(alpha),
                            col.blended(withFraction: 0.45, of: .black)!.withAlphaComponent(alpha)])!
            .draw(fromCenter: c, radius: outer, toCenter: c, radius: inner, options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
        NSGraphicsContext.restoreGraphicsState()
        // Glass edge on each segment
        NSColor.white.withAlphaComponent(hot ? 0.55 : 0.22).setStroke()
        p.lineWidth = 3
        p.stroke()
    }

    // Frosted center disc
    let discR: CGFloat = 122
    let disc = NSBezierPath(ovalIn: NSRect(x: c.x - discR, y: c.y - discR, width: discR * 2, height: discR * 2))
    NSGraphicsContext.saveGraphicsState()
    let ds = NSShadow()
    ds.shadowBlurRadius = 30
    ds.shadowOffset = NSSize(width: 0, height: -8)
    ds.shadowColor = NSColor.black.withAlphaComponent(0.5)
    ds.set()
    NSGradient(colors: [rgb(255, 255, 255, 0.97), rgb(214, 222, 245, 0.92)])!.draw(in: disc, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // "Turn" arrow inside the disc
    let ink = rgb(22, 26, 48)
    let arcR: CGFloat = 62
    let arrow = NSBezierPath()
    arrow.appendArc(withCenter: c, radius: arcR, startAngle: 120, endAngle: -150, clockwise: true)
    arrow.lineWidth = 22
    arrow.lineCapStyle = .round
    ink.setStroke()
    arrow.stroke()
    let tipA = CGFloat(-150) * .pi / 180
    let tip = NSPoint(x: c.x + cos(tipA) * arcR, y: c.y + sin(tipA) * arcR)
    let head = NSBezierPath()
    // tangent direction at the end of a clockwise arc
    let tx = sin(tipA), ty = -cos(tipA)
    let nx = cos(tipA), ny = sin(tipA)
    head.move(to: NSPoint(x: tip.x + tx * 34, y: tip.y + ty * 34))
    head.line(to: NSPoint(x: tip.x + nx * 30 - tx * 6, y: tip.y + ny * 30 - ty * 6))
    head.line(to: NSPoint(x: tip.x - nx * 30 - tx * 6, y: tip.y - ny * 30 - ty * 6))
    head.close()
    ink.setFill()
    head.fill()

    // Gloss
    let gloss = NSBezierPath(ovalIn: NSRect(x: body.minX - 120, y: c.y + 40, width: body.width + 240, height: body.height))
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.10), NSColor.white.withAlphaComponent(0)])!.draw(in: gloss, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Hairline rim
    NSColor.white.withAlphaComponent(0.14).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 185, yRadius: 185)
    rim.lineWidth = 3
    rim.stroke()
    return true
}

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
