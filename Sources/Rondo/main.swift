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

// Rondo --check-update [pretend-current-version]: queries GitHub and prints the result (testing)
if args.count >= 2, args[1] == "--check-update" {
    let current = args.count >= 3 ? args[2] : Updater.currentVersion
    Updater.fetchLatest { r in
        switch r {
        case .success(let rel):
            print("latest=\(rel.version) current=\(current) newer=\(Updater.isNewer(rel.version, than: current))")
            print("download=\(rel.downloadURL?.absoluteString ?? rel.pageURL.absoluteString)")
            exit(0)
        case .failure(let e): print("errore: \(e.localizedDescription)"); exit(1)
        }
    }
    RunLoop.main.run()
}

// Rondo --snapshot-about <out.png>
if args.count >= 3, args[1] == "--snapshot-about" {
    let host = NSHostingView(rootView: AboutView())
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    win.contentView = host
    host.layoutSubtreeIfNeeded()
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
    exit(0)
}

// Rondo --snapshot-installer <out.png>
if args.count >= 3, args[1] == "--snapshot-installer" {
    let host = NSHostingView(rootView: FFmpegInstallView(model: FFmpegInstaller.shared))
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    win.contentView = host
    host.layoutSubtreeIfNeeded()
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
    exit(0)
}

// Rondo --apply-update <app> <dmg-url> <sig-url> <version>: runs the automatic install on <app> (testing)
if args.count >= 6, args[1] == "--apply-update" {
    let r = Updater.Release(version: args[5], notes: "", pageURL: URL(string: "https://example.invalid")!,
                            downloadURL: URL(string: args[3]), signatureURL: URL(string: args[4]))
    do {
        try AutoInstaller.install(r, app: URL(fileURLWithPath: args[2])) { _ in }
        print("installed")
        exit(0)
    } catch {
        print("errore: \(error.localizedDescription)")
        exit(1)
    }
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
