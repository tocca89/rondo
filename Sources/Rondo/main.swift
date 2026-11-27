import AppKit
import SwiftUI

let app = NSApplication.shared
Prefs.registerDefaults()

// Command-line mode, handy for scripts and tests:
//   Rondo --list <convert|tools|actions> <file…>
//   Rondo --run  <convert|tools> "<Item title>" <file…>
let args = CommandLine.arguments
if args.count >= 4, args[1] == "--list" || args[1] == "--run" {
    let kinds: [String: WheelKind] = ["convert": .convert, "tools": .tools, "actions": .actions]
    guard let kind = kinds[args[2]] else { print("tipo sconosciuto: \(args[2])"); exit(2) }
    if args[1] == "--list" {
        let urls = args[3...].map { URL(fileURLWithPath: $0).absoluteURL }
        print(Catalog.items(kind, for: urls).map(\.title).joined(separator: "\n"))
        exit(0)
    }
    let urls = args[4...].map { URL(fileURLWithPath: $0).absoluteURL }
    guard let item = Catalog.items(kind, for: urls).first(where: { $0.title == args[3] }) else {
        print("voce non disponibile: \(args[3])"); exit(2)
    }
    do {
        for out in try item.run(urls) { print(out.path) }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("errore: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

// Rondo --snapshot <kind> <out.png> <highlight> <file…>: renders the wheel to a PNG (design check)
if args.count >= 6, args[1] == "--snapshot" {
    let kind: WheelKind = ["tools": .tools, "actions": .actions][args[2]] ?? .convert
    let urls = args[5...].map { URL(fileURLWithPath: $0).absoluteURL }
    let v = WheelView(frame: NSRect(origin: .zero, size: WheelView.preferredSize))
    v.kind = kind; v.urls = urls; v.items = Catalog.items(kind, for: urls); v.highlighted = Int(args[4])
    let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    NSColor(calibratedRed: 0.35, green: 0.45, blue: 0.55, alpha: 1).setFill(); v.bounds.fill() // fake desktop
    NSColor(white: 0.12, alpha: 0.9).setFill()
    NSBezierPath(ovalIn: NSRect(x: v.ringCenter.x - v.outerR, y: v.ringCenter.y - v.outerR, width: v.outerR * 2, height: v.outerR * 2)).fill()
    NSGraphicsContext.restoreGraphicsState()
    v.cacheDisplay(in: v.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
    exit(0)
}

// Rondo --snapshot-welcome <out.png>: renders the welcome window (design check)
if args.count >= 3, args[1] == "--snapshot-welcome" {
    let host = NSHostingView(rootView: WelcomeView(openSettings: {}, close: {}, practice: PracticeModel()))
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    win.contentView = host
    host.layoutSubtreeIfNeeded()
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
    exit(0)
}

// Rondo --demo <convert|tools|actions> <file…>: opens the wheel at launch (for screenshots/testing)
if args.count >= 4, args[1] == "--demo" {
    let kind: WheelKind = ["tools": .tools, "actions": .actions][args[2]] ?? .convert
    let urls = args[3...].map { URL(fileURLWithPath: $0).absoluteURL }
    Prefs.d.set(false, forKey: "showWelcome")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        WheelController.shared.showInteractive(kind: kind, urls: urls)
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
