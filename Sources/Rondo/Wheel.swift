import AppKit

extension Notification.Name {
    static let rondoWheelShown = Notification.Name("rondoWheelShown")
    static let rondoDragStarted = Notification.Name("rondoDragStarted")
    static let rondoJobFinished = Notification.Name("rondoJobFinished")
}

// MARK: - Log

enum Log {
    static let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/Rondo.log")
    private static let df: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()

    /// Enable with: defaults write app.rondo.Rondo debugLog -bool true
    static func write(_ msg: String) {
        guard UserDefaults.standard.bool(forKey: "debugLog") else { return }
        let line = "\(df.string(from: Date())) \(msg)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(line.utf8).write(to: url)
        }
    }
}

// MARK: - Drag monitor

/// Watches for file drags anywhere in the system without special permissions:
/// polls the global mouse-button state, the shared drag pasteboard and the modifier keys
/// (via CGEventSource, which reflects the real hardware state even while another app owns the drag).
final class DragMonitor {
    var onTap: ((WheelKind, [URL]) -> Void)?
    var onEnd: (() -> Void)?

    private let pb = NSPasteboard(name: .drag)
    private var idleCount = -1          // drag-pasteboard changeCount seen while the button was up
    private var baseline: Int?
    private var timer: Timer?
    private var fast = false
    private var pressed = false
    private var active = false
    private var loggedNoFiles = false
    private var urls: [URL] = []
    private var lastFlags: NSEvent.ModifierFlags = []
    private var monitors: [Any] = []

    func start() {
        idleCount = pb.changeCount
        schedule(fast: false)
        // Mouse-down monitors only speed things up; polling works even without them.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged], handler: { [weak self] _ in
            self?.schedule(fast: true)
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged], handler: { [weak self] e in
            self?.schedule(fast: true); return e
        }) { monitors.append(m) }
        Log.write("DragMonitor avviato (changeCount drag=\(idleCount))")
    }

    private func schedule(fast: Bool) {
        if timer != nil && self.fast == fast { return }
        timer?.invalidate()
        self.fast = fast
        let interval = fast ? 1.0 / 50.0 : 1.0 / 12.0
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var currentFlags: NSEvent.ModifierFlags {
        let f = CGEventSource.flagsState(.combinedSessionState)
        var m: NSEvent.ModifierFlags = []
        if f.contains(.maskShift) { m.insert(.shift) }
        if f.contains(.maskCommand) { m.insert(.command) }
        if f.contains(.maskControl) { m.insert(.control) }
        if f.contains(.maskAlternate) { m.insert(.option) }
        return m
    }

    private func readFileURLs() -> [URL] {
        if let u = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !u.isEmpty {
            return u
        }
        // Fallbacks for older-style drags
        if let names = pb.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String], !names.isEmpty {
            return names.map { URL(fileURLWithPath: $0) }
        }
        let items = pb.pasteboardItems ?? []
        return items.compactMap { $0.string(forType: .fileURL).flatMap { URL(string: $0) } }.filter(\.isFileURL)
    }

    private func tick() {
        let down = CGEventSource.buttonState(.combinedSessionState, button: .left)
        if !down {
            if pressed { mouseUp() }
            if !fast { idleCount = pb.changeCount } else { schedule(fast: false) }
            return
        }
        guard Prefs.enabled else { return }
        if !pressed {
            pressed = true
            baseline = idleCount
            active = false
            loggedNoFiles = false
            schedule(fast: true)
        }
        if !active {
            let cc = pb.changeCount
            guard let b = baseline, cc != b else { return }
            let u = readFileURLs()
            if u.isEmpty {
                if !loggedNoFiles {
                    loggedNoFiles = true
                    Log.write("drag senza file (tipi: \(pb.types?.map(\.rawValue).joined(separator: ", ") ?? "-"))")
                }
                return // the pasteboard may still be filling up: retry next tick
            }
            urls = u
            active = true
            lastFlags = currentFlags // keys already held when the drag started don't count
            NotificationCenter.default.post(name: .rondoDragStarted, object: u)
            Log.write("drag di file rilevato: \(u.map(\.lastPathComponent).joined(separator: ", "))")
            return
        }
        let f = currentFlags
        let newly = f.subtracting(lastFlags)
        lastFlags = f
        guard !newly.isEmpty else { return }
        for kind in WheelKind.allCases where newly.contains(Prefs.key(for: kind).flag) {
            Log.write("tasto premuto → ruota \(kind.title)")
            onTap?(kind, urls)
            break
        }
    }

    private func mouseUp() {
        pressed = false
        if active { Log.write("drag terminato"); onEnd?() }
        active = false
        baseline = nil
        urls = []
        idleCount = pb.changeCount
    }
}

// MARK: - Controller

final class WheelController {
    static let shared = WheelController()

    private var panel: WheelPanel?
    private var view: WheelView!
    private var interactive = false

    var isVisible: Bool { panel?.isVisible ?? false }

    private func build() {
        let size = WheelView.preferredSize
        let p = WheelPanel(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        let v = WheelView(frame: container.bounds)

        let blur = NSVisualEffectView(frame: container.bounds)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .vibrantDark)
        blur.maskImage = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: v.ringCenter.x - v.outerR, y: v.ringCenter.y - v.outerR,
                                        width: v.outerR * 2, height: v.outerR * 2)).fill()
            return true
        }
        container.addSubview(blur)
        container.addSubview(v)
        p.contentView = container

        v.onExecute = { [weak self] item, urls in
            self?.hide(accepted: true)
            Engine.execute(item, urls: urls)
        }
        v.onCancel = { [weak self] in self?.hide(accepted: false) }
        v.onSwitch = { [weak self] kind in self?.switchKind(kind) }
        p.onResign = { [weak self] in
            if self?.interactive == true { self?.hide() }
        }
        panel = p
        view = v
    }

    /// Called while a file drag is in progress and a modifier key was tapped.
    func showForDrag(kind: WheelKind, urls: [URL]) {
        Log.write("mostro ruota \(kind.title) (visibile: \(isVisible))")
        if isVisible && !interactive { switchKind(kind, urls: urls); return }
        present(kind: kind, urls: urls, at: NSEvent.mouseLocation, interactive: false)
    }

    /// Keyboard/mouse mode (menu bar or hot key): click or use arrows + Enter.
    func showInteractive(kind: WheelKind = .convert, urls: [URL]) {
        present(kind: kind, urls: urls, at: NSEvent.mouseLocation, interactive: true)
    }

    func dragEnded() {
        guard !interactive else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            if self?.interactive == false { self?.hide() }
        }
    }

    func switchKind(_ kind: WheelKind, urls: [URL]? = nil) {
        guard let v = view else { return }
        if let urls { v.urls = urls }
        v.kind = kind
        v.items = Catalog.items(kind, for: v.urls)
        v.highlighted = interactive && !v.items.isEmpty ? 0 : nil
        v.startAppear()
        NotificationCenter.default.post(name: .rondoWheelShown, object: nil)
    }

    private func present(kind: WheelKind, urls: [URL], at point: NSPoint, interactive: Bool) {
        if panel == nil { build() }
        guard let panel, let view else { return }
        self.interactive = interactive
        view.interactive = interactive
        view.urls = urls
        switchKind(kind)

        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        var origin = NSPoint(x: point.x - view.ringCenter.x, y: point.y - view.ringCenter.y)
        if let vf = screen?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX), vf.maxX - panel.frame.width)
            origin.y = min(max(origin.y, vf.minY), vf.maxY - panel.frame.height)
        }
        panel.setFrameOrigin(origin)
        panel.alphaValue = 1
        hiding = false
        if interactive {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(view)
        } else {
            panel.orderFrontRegardless()
        }
        // Springy pop-in around the cursor
        guard let layer = panel.contentView?.layer else { return }
        anchor(layer, at: view.ringCenter)
        layer.removeAllAnimations()
        layer.transform = CATransform3DIdentity
        layer.opacity = 1
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.78
        spring.toValue = 1
        spring.mass = 1
        spring.stiffness = 320
        spring.damping = 17
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "pop")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.12
        layer.add(fade, forKey: "fade")
    }

    private var hiding = false

    private func anchor(_ layer: CALayer, at p: CGPoint) {
        let b = layer.bounds
        guard b.width > 0, b.height > 0 else { return }
        layer.anchorPoint = CGPoint(x: p.x / b.width, y: p.y / b.height)
        layer.position = p
    }

    /// accepted = the file was dropped on a slice: the wheel collapses into it. Otherwise it simply fades away.
    func hide(accepted: Bool = false) {
        interactive = false
        if hiding { return }
        guard let panel, panel.isVisible, let layer = panel.contentView?.layer else {
            panel?.orderOut(nil); view?.highlighted = nil; return
        }
        hiding = true
        var target = view.ringCenter
        if accepted, let h = view.highlighted, !view.items.isEmpty {
            let a = (90 - CGFloat(h) * 360 / CGFloat(view.items.count)) * .pi / 180
            target = CGPoint(x: view.ringCenter.x + cos(a) * 115, y: view.ringCenter.y + sin(a) * 115)
            view.flash()
        }
        anchor(layer, at: target)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.hiding else { return }
            self.hiding = false
            panel.orderOut(nil)
            layer.removeAllAnimations()
            layer.transform = CATransform3DIdentity
            layer.opacity = 1
            self.view?.highlighted = nil
        }
        let dur = accepted ? 0.24 : 0.14
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.toValue = accepted ? 0.12 : 0.9
        scale.beginTime = CACurrentMediaTime() + (accepted ? 0.06 : 0)
        scale.duration = dur
        scale.timingFunction = CAMediaTimingFunction(name: .easeIn)
        scale.fillMode = .both
        scale.isRemovedOnCompletion = false
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.toValue = 0
        fade.beginTime = scale.beginTime
        fade.duration = dur
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        fade.fillMode = .both
        fade.isRemovedOnCompletion = false
        layer.add(scale, forKey: "out-scale")
        layer.add(fade, forKey: "out-fade")
        CATransaction.commit()
    }
}

final class WheelPanel: NSPanel {
    var onResign: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func resignKey() {
        super.resignKey()
        onResign?()
    }
}

// MARK: - Wheel view

final class WheelView: NSView {
    static let outer: CGFloat = 172
    static let preferredSize = NSSize(width: outer * 2 + 24, height: outer * 2 + 24 + 40)

    let innerR: CGFloat = 54
    let outerR: CGFloat = WheelView.outer
    var ringCenter: NSPoint { NSPoint(x: bounds.midX, y: bounds.maxY - 12 - outerR) }

    var kind: WheelKind = .convert
    var items: [WheelItem] = []
    var urls: [URL] = []
    var interactive = false
    var highlighted: Int? {
        didSet {
            guard oldValue != highlighted else { return }
            needsDisplay = true
            if highlighted != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            startTimer()
        }
    }

    // MARK: Animation state

    private var appearStart: CFTimeInterval = 0
    private var glow: [CGFloat] = []          // per-slice highlight amount, eased toward 0/1
    private var flashUntil: CFTimeInterval = 0
    private var animTimer: Timer?

    func startAppear() {
        appearStart = CACurrentMediaTime()
        glow = Array(repeating: 0, count: items.count)
        startTimer()
        needsDisplay = true
    }

    func flash() {
        flashUntil = CACurrentMediaTime() + 0.12
        needsDisplay = true
    }

    private func startTimer() {
        guard animTimer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.animTick() }
        RunLoop.main.add(t, forMode: .common)
        animTimer = t
    }

    private func animTick() {
        if glow.count != items.count { glow = Array(repeating: 0, count: items.count) }
        var moving = CACurrentMediaTime() - appearStart < 0.25 + Double(items.count) * 0.025
        for i in glow.indices {
            let target: CGFloat = i == highlighted ? 1 : 0
            let d = target - glow[i]
            if abs(d) > 0.01 { glow[i] += d * 0.35; moving = true } else { glow[i] = target }
        }
        needsDisplay = true
        if !moving { animTimer?.invalidate(); animTimer = nil }
    }

    /// 0…1 appear progress for slice i (staggered, slight overshoot)
    private func appear(_ i: Int) -> (alpha: CGFloat, offset: CGFloat) {
        let t = (CACurrentMediaTime() - appearStart - Double(i) * 0.025) / 0.22
        let p = CGFloat(min(max(t, 0), 1))
        let c1: CGFloat = 1.70158, c3 = c1 + 1
        let back = 1 + c3 * pow(p - 1, 3) + c1 * pow(p - 1, 2) // easeOutBack
        return (min(1, p * 1.6), (1 - back) * 24)
    }

    var onExecute: ((WheelItem, [URL]) -> Void)?
    var onCancel: (() -> Void)?
    var onSwitch: ((WheelKind) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Geometry

    func index(at p: NSPoint) -> Int? {
        let n = items.count
        guard n > 0 else { return nil }
        let dx = p.x - ringCenter.x, dy = p.y - ringCenter.y
        if hypot(dx, dy) < innerR { return nil }
        var cw = 90 - atan2(dy, dx) * 180 / .pi
        cw = cw.truncatingRemainder(dividingBy: 360)
        if cw < 0 { cw += 360 }
        let step = 360 / CGFloat(n)
        return Int((cw + step / 2) / step) % n
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let c = ringCenter
        let ringRect = NSRect(x: c.x - outerR, y: c.y - outerR, width: outerR * 2, height: outerR * 2)
        NSColor(white: 0.05, alpha: 0.35).setFill()
        NSBezierPath(ovalIn: ringRect).fill()

        let n = items.count
        if n > 0 {
            let step = 360 / CGFloat(n)
            for i in 0..<n {
                let mid = 90 - CGFloat(i) * step
                let g = i < glow.count ? glow[i] : (i == highlighted ? 1 : 0)
                if g > 0.01 {
                    let path = NSBezierPath()
                    let gap = min(1.2, step / 8)
                    path.appendArc(withCenter: c, radius: outerR - 4 + 6 * g, startAngle: mid + step / 2 - gap, endAngle: mid - step / 2 + gap, clockwise: true)
                    path.appendArc(withCenter: c, radius: innerR + 4, startAngle: mid - step / 2 + gap, endAngle: mid + step / 2 - gap, clockwise: false)
                    path.close()
                    NSGraphicsContext.saveGraphicsState()
                    let sh = NSShadow()
                    sh.shadowColor = NSColor.controlAccentColor.withAlphaComponent(0.7 * g)
                    sh.shadowBlurRadius = 14
                    sh.set()
                    let flashing = i == highlighted && CACurrentMediaTime() < flashUntil
                    let base = flashing ? NSColor.white : NSColor.controlAccentColor
                    NSGradient(colors: [base.withAlphaComponent(0.95 * g),
                                        base.blended(withFraction: 0.25, of: .white)?.withAlphaComponent(0.95 * g) ?? base])?
                        .draw(in: path, relativeCenterPosition: .zero)
                    NSGraphicsContext.restoreGraphicsState()
                }
                if n > 1 {
                    let a = (mid + step / 2) * .pi / 180
                    let line = NSBezierPath()
                    line.move(to: NSPoint(x: c.x + cos(a) * (innerR + 8), y: c.y + sin(a) * (innerR + 8)))
                    line.line(to: NSPoint(x: c.x + cos(a) * (outerR - 8), y: c.y + sin(a) * (outerR - 8)))
                    NSColor(white: 1, alpha: 0.10).setStroke()
                    line.lineWidth = 1
                    line.stroke()
                }
                let ap = appear(i)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.cgContext.setAlpha(ap.alpha)
                drawItem(items[i], angle: mid, count: n, selected: i == highlighted, inset: ap.offset)
                NSGraphicsContext.restoreGraphicsState()
            }
        } else {
            let msg = NSAttributedString(string: L("Nessuna opzione\nper questi file"), attributes: textAttrs(11, .medium, alpha: 0.7))
            let r = msg.boundingRect(with: NSSize(width: 160, height: 60), options: .usesLineFragmentOrigin)
            msg.draw(with: NSRect(x: c.x - 80, y: c.y + innerR + 30, width: 160, height: r.height), options: .usesLineFragmentOrigin)
        }

        // Ring borders
        NSColor(white: 1, alpha: 0.16).setStroke()
        let border = NSBezierPath(ovalIn: ringRect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()

        // Center disc
        let cr = innerR - 2
        let disc = NSBezierPath(ovalIn: NSRect(x: c.x - cr, y: c.y - cr, width: cr * 2, height: cr * 2))
        NSColor(white: 0, alpha: 0.35).setFill()
        disc.fill()
        NSColor(white: 1, alpha: 0.12).setStroke()
        disc.stroke()
        drawCenter(c)
        drawHints(c)
    }

    private func textAttrs(_ size: CGFloat, _ weight: NSFont.Weight, alpha: CGFloat = 1, align: NSTextAlignment = .center) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.alignment = align
        p.lineBreakMode = .byWordWrapping
        return [.font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: NSColor(white: 1, alpha: alpha),
                .paragraphStyle: p]
    }

    private func drawItem(_ item: WheelItem, angle: CGFloat, count n: Int, selected: Bool, inset: CGFloat = 0) {
        let c = ringCenter
        let r = (innerR + outerR) / 2 + 2 - inset
        let rad = angle * .pi / 180
        let p = NSPoint(x: c.x + cos(rad) * r, y: c.y + sin(rad) * r)
        let maxW = min(96, 2 * .pi * r / CGFloat(n) - 10)

        if item.symbol.isEmpty {
            // Format name, big
            let s = NSAttributedString(string: item.title, attributes: textAttrs(item.title.count > 5 ? 12.5 : 15, .bold))
            let b = s.boundingRect(with: NSSize(width: maxW + 10, height: 40), options: .usesLineFragmentOrigin)
            s.draw(with: NSRect(x: p.x - (maxW + 10) / 2, y: p.y - b.height / 2, width: maxW + 10, height: b.height),
                   options: .usesLineFragmentOrigin)
            return
        }
        let cfg = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        if let img = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)?.withSymbolConfiguration(cfg) {
            let s = img.size
            img.draw(in: NSRect(x: p.x - s.width / 2, y: p.y + 3, width: s.width, height: s.height))
        }
        // Shrink the font until the longest word fits (long German/French words must not break mid-word)
        var fontSize: CGFloat = 10.5
        let words = item.title.split(separator: " ").map(String.init)
        while fontSize > 8, words.contains(where: {
            NSAttributedString(string: $0, attributes: textAttrs(fontSize, .semibold)).size().width > maxW - 2
        }) { fontSize -= 0.5 }
        let label = NSAttributedString(string: item.title, attributes: textAttrs(fontSize, .semibold, alpha: selected ? 1 : 0.88))
        let b = label.boundingRect(with: NSSize(width: maxW, height: 30), options: .usesLineFragmentOrigin)
        label.draw(with: NSRect(x: p.x - maxW / 2, y: p.y - 2 - min(b.height, 28), width: maxW, height: min(b.height, 28)),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private func drawCenter(_ c: NSPoint) {
        let w = innerR * 2 - 14
        let title: String
        var symbol: String? = kind.symbol
        if let h = highlighted, h < items.count {
            title = items[h].title
            symbol = nil
        } else {
            title = kind.title
        }
        if let symbol {
            let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(white: 1, alpha: 0.9)]))
            if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
                img.draw(in: NSRect(x: c.x - img.size.width / 2, y: c.y + 10, width: img.size.width, height: img.size.height))
            }
        }
        let t = NSAttributedString(string: title, attributes: textAttrs(11.5, .bold))
        let tb = t.boundingRect(with: NSSize(width: w, height: 40), options: .usesLineFragmentOrigin)
        let ty = symbol == nil ? c.y - tb.height / 2 + 6 : c.y - 8
        t.draw(with: NSRect(x: c.x - w / 2, y: ty, width: w, height: min(tb.height, 30)),
               options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

        let sub = urls.count == 1 ? urls[0].lastPathComponent : L("%d elementi", urls.count)
        let sAttrs = textAttrs(9, .regular, alpha: 0.6)
        (sAttrs[.paragraphStyle] as? NSMutableParagraphStyle)?.lineBreakMode = .byTruncatingMiddle
        NSAttributedString(string: sub, attributes: sAttrs)
            .draw(in: NSRect(x: c.x - w / 2, y: c.y - 26, width: w, height: 13))
    }

    private func drawHints(_ c: NSPoint) {
        let s = NSMutableAttributedString()
        for k in WheelKind.allCases {
            if s.length > 0 { s.append(NSAttributedString(string: "    ", attributes: textAttrs(11, .regular))) }
            let active = k == kind
            s.append(NSAttributedString(string: "\(Prefs.key(for: k).glyph) \(k.title)",
                                        attributes: textAttrs(11, active ? .bold : .medium, alpha: active ? 1 : 0.55)))
        }
        let size = s.size()
        let box = NSRect(x: c.x - size.width / 2 - 12, y: c.y - outerR - 12 - size.height - 8,
                         width: size.width + 24, height: size.height + 8)
        NSColor(white: 0.08, alpha: 0.82).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        s.draw(at: NSPoint(x: box.minX + 12, y: box.minY + 4))
    }

    // MARK: Drag & drop

    private func operation(for info: NSDraggingInfo) -> NSDragOperation {
        let mask = info.draggingSourceOperationMask
        for op in [NSDragOperation.copy, .generic, .move, .link] where mask.contains(op) { return op }
        return .every
    }

    private func update(_ info: NSDraggingInfo) -> NSDragOperation {
        highlighted = index(at: convert(info.draggingLocation, from: nil))
        return highlighted == nil ? [] : operation(for: info)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Log.write("drag entrato nella ruota (mask \(sender.draggingSourceOperationMask.rawValue))")
        return update(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = nil }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { highlighted != nil }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let i = highlighted, i < items.count else { return false }
        let dropped = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                             options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let item = items[i]
        Log.write("rilasciato su \(item.title)")
        let target = dropped.isEmpty ? urls : dropped
        DispatchQueue.main.async { self.onExecute?(item, target) }
        return true
    }

    // MARK: Mouse & keyboard (interactive mode)

    override func mouseMoved(with event: NSEvent) {
        guard interactive else { return }
        highlighted = index(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let c = ringCenter
        if hypot(p.x - c.x, p.y - c.y) > outerR { onCancel?(); return }
        if let i = index(at: p), i < items.count { onExecute?(items[i], urls) } else { onSwitch?(kind.next) }
    }

    override func keyDown(with event: NSEvent) {
        let n = items.count
        switch event.keyCode {
        case 53: onCancel?() // esc
        case 36, 76: // return / enter
            if let h = highlighted, h < n { onExecute?(items[h], urls) }
        case 48: onSwitch?(event.modifierFlags.contains(.shift) ? kind.next.next : kind.next) // tab
        case 124, 125: if n > 0 { highlighted = ((highlighted ?? -1) + 1) % n } // right / down
        case 123, 126: if n > 0 { highlighted = ((highlighted ?? 0) - 1 + n) % n } // left / up
        default:
            if let ch = event.charactersIgnoringModifiers, let d = Int(ch), d >= 1, d <= n { onExecute?(items[d - 1], urls) }
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard interactive else { return }
        let f = event.modifierFlags
        for k in WheelKind.allCases where f.contains(Prefs.key(for: k).flag) && k != kind {
            onSwitch?(k)
            return
        }
    }
}
