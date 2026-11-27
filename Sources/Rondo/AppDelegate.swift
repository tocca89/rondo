import AppKit
import Carbon
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let monitor = DragMonitor()
    private var hotKey: HotKey?
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var enabledItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        buildMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.statusIcon()
        statusItem.button?.toolTip = "Rondo"
        let menu = NSMenu()
        menu.delegate = self
        fillStatusMenu(menu)
        statusItem.menu = menu

        monitor.onTap = { kind, urls in WheelController.shared.showForDrag(kind: kind, urls: urls) }
        monitor.onEnd = { WheelController.shared.dragEnded() }
        monitor.start()
        NotificationCenter.default.addObserver(forName: Jobs.changed, object: nil, queue: .main) { [weak self] _ in
            self?.jobsChanged()
        }

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.openFinderSelection()
        }

        if Prefs.d.bool(forKey: "showWelcome") { showWelcome() }
        Updater.startAutomaticChecks()
    }

    /// Rebuilt every time it opens, so a language change applies immediately.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        fillStatusMenu(menu)
        buildMainMenu()
    }

    private func fillStatusMenu(_ menu: NSMenu) {
        menu.addItem(NSMenuItem(title: L("Informazioni su Rondo"), action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L("Controlla aggiornamenti…"), action: #selector(checkUpdates), keyEquivalent: ""))
        menu.addItem(.separator())
        enabledItem = NSMenuItem(title: L("Ruote durante il trascinamento"), action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.state = Prefs.enabled ? .on : .off
        menu.addItem(enabledItem)
        menu.addItem(.separator())
        let sel = NSMenuItem(title: L("Apri selezione del Finder"), action: #selector(openFinderSelection), keyEquivalent: "r")
        sel.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(sel)
        menu.addItem(NSMenuItem(title: L("Scegli file…"), action: #selector(chooseFiles), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L("Mostra Float"), action: #selector(showFloat), keyEquivalent: ""))
        if Shell.ffmpeg == nil {
            menu.addItem(NSMenuItem(title: L("Installa ffmpeg…"), action: #selector(installFFmpeg), keyEquivalent: ""))
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Come si usa"), action: #selector(showWelcome), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L("Impostazioni…"), action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Esci da Rondo"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
    }

    // MARK: Actions

    @objc private func toggleEnabled() { Prefs.enabled.toggle() }

    @objc func openFinderSelection() {
        let urls = Self.finderSelection()
        if urls.isEmpty { chooseFiles() } else { WheelController.shared.showInteractive(urls: urls) }
    }

    @objc private func chooseFiles() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        p.message = L("Scegli i file da convertire")
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, !p.urls.isEmpty else { return }
        DispatchQueue.main.async { WheelController.shared.showInteractive(urls: p.urls) }
    }

    @objc private func showFloat() { FloatShelf.shared.show() }

    @objc func showAbout() {
        aboutWindow = present(aboutWindow, title: L("Informazioni su Rondo"), view: AboutView())
    }

    @objc private func installFFmpeg() { FFmpegInstaller.shared.show() }

    @objc private func checkUpdates() { Updater.check(userInitiated: true) }

    @objc func showSettings() {
        settingsWindow = present(settingsWindow, title: L("Impostazioni di Rondo"), view: SettingsView())
    }

    @objc func showWelcome() {
        welcomeWindow?.close()
        welcomeWindow = present(nil, title: L("Benvenuto in Rondo"), view: WelcomeView(
            openSettings: { [weak self] in self?.showSettings() },
            close: { [weak self] in
                Prefs.d.set(false, forKey: "showWelcome")
                self?.welcomeWindow?.close()
            },
            practice: PracticeModel()))
    }

    private func present<V: View>(_ existing: NSWindow?, title: String, view: V) -> NSWindow {
        let w = existing ?? {
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = title
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            return w
        }()
        w.title = title
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        return w
    }

    // MARK: Helpers

    static func finderSelection() -> [URL] {
        let src = """
        tell application "Finder"
            set out to ""
            repeat with i in (get selection)
                set out to out & POSIX path of (i as alias) & linefeed
            end repeat
            return out
        end tell
        """
        var err: NSDictionary?
        let r = NSAppleScript(source: src)?.executeAndReturnError(&err)
        return (r?.stringValue ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }

    /// Menu-bar icon while jobs run: a ring that fills up (or spins when progress is unknown).
    static func progressIcon(fraction: Double?, phase: Double) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            let c = NSPoint(x: r.midX, y: r.midY)
            NSColor.black.withAlphaComponent(0.3).setStroke()
            let bg = NSBezierPath(ovalIn: NSRect(x: c.x - 6.5, y: c.y - 6.5, width: 13, height: 13))
            bg.lineWidth = 2
            bg.stroke()
            NSColor.black.setStroke()
            let arc = NSBezierPath()
            if let f = fraction {
                arc.appendArc(withCenter: c, radius: 6.5, startAngle: 90, endAngle: 90 - 360 * CGFloat(max(0.03, f)), clockwise: true)
            } else {
                let start = CGFloat(-phase * 360).truncatingRemainder(dividingBy: 360)
                arc.appendArc(withCenter: c, radius: 6.5, startAngle: start, endAngle: start + 100)
            }
            arc.lineWidth = 2.6
            arc.lineCapStyle = .round
            arc.stroke()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - 1.6, y: c.y - 1.6, width: 3.2, height: 3.2)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }

    private var iconTimer: Timer?

    private func jobsChanged() {
        if Jobs.shared.active.isEmpty {
            iconTimer?.invalidate()
            iconTimer = nil
            statusItem.button?.image = Self.statusIcon()
            return
        }
        guard iconTimer == nil else { return }
        let start = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.statusItem.button?.image = Self.progressIcon(fraction: Jobs.shared.fraction, phase: (CACurrentMediaTime() - start) * 1.2)
        }
        RunLoop.main.add(t, forMode: .common)
        iconTimer = t
    }

    static func statusIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            let c = NSPoint(x: r.midX, y: r.midY)
            NSColor.black.setStroke()
            for i in 0..<6 {
                let start = CGFloat(i) * 60 + 8
                let p = NSBezierPath()
                p.appendArc(withCenter: c, radius: 6.5, startAngle: start, endAngle: start + 44)
                p.lineWidth = i == 0 ? 3.2 : 2
                p.lineCapStyle = .round
                p.stroke()
            }
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - 1.6, y: c.y - 1.6, width: 3.2, height: 3.2)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }

    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let about = NSMenuItem(title: L("Informazioni su Rondo"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: L("Esci da Rondo"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: L("Modifica"))
        edit.addItem(NSMenuItem(title: L("Taglia"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: L("Copia"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: L("Incolla"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: L("Seleziona tutto"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        edit.addItem(NSMenuItem(title: L("Chiudi finestra"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}

// MARK: - Global hot key (Carbon, no permissions needed)

final class HotKey {
    private var ref: EventHotKeyRef?
    private static var handler: (() -> Void)?

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        HotKey.handler = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.handler?() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x5255_4F54), id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }
}

// MARK: - Settings

final class SystemModel: ObservableObject {
    static let shared = SystemModel()
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?
}

struct SettingsView: View {
    @AppStorage("convertKey") private var convertKey = 0
    @AppStorage("toolsKey") private var toolsKey = 1
    @AppStorage("actionsKey") private var actionsKey = 2
    @AppStorage("outputMode") private var outputMode = 0
    @AppStorage("customFolder") private var customFolder = ""
    @AppStorage("quality") private var quality = 0.85
    @AppStorage("pdfDPI") private var pdfDPI = 300.0
    @AppStorage("revealAfter") private var revealAfter = false
    @AppStorage("playSound") private var playSound = true
    @AppStorage("enabled") private var enabled = true
    @AppStorage("ffmpegPath") private var ffmpegPath = ""
    @AppStorage("language") private var language = ""
    @AppStorage("autoUpdate") private var autoUpdate = true
    @ObservedObject private var sys = SystemModel.shared

    var body: some View {
        Form {
            Section(L("Lingua")) {
                Picker(L("Lingua"), selection: Binding(get: { language }, set: { Lang.apply($0); language = $0 })) {
                    Text(L("Automatica (sistema)")).tag("")
                    ForEach(Lang.all, id: \.code) { l in Text(l.name).tag(l.code) }
                }
                Text(L("Alcuni testi di sistema cambiano al prossimo avvio.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Ruote")) {
                Toggle(L("Mostra le ruote mentre trascini un file"), isOn: $enabled)
                keyPicker(L("Converti"), $convertKey)
                keyPicker(L("Strumenti"), $toolsKey)
                keyPicker(L("Azioni"), $actionsKey)
                if Set([convertKey, toolsKey, actionsKey]).count < 3 {
                    Label(L("Due ruote usano lo stesso tasto"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            Section(L("Output")) {
                Picker(L("Salva i file"), selection: $outputMode) {
                    Text(L("Accanto all'originale")).tag(0)
                    Text(L("In Download")).tag(1)
                    Text(L("In una cartella…")).tag(2)
                }
                if outputMode == 2 {
                    HStack {
                        Text(customFolder.isEmpty ? L("Nessuna cartella") : customFolder)
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Scegli…")) {
                            let p = NSOpenPanel()
                            p.canChooseFiles = false
                            p.canChooseDirectories = true
                            p.canCreateDirectories = true
                            if p.runModal() == .OK, let u = p.url { customFolder = u.path }
                        }
                    }
                }
                HStack {
                    Text(L("Qualità JPG/HEIC/WebP"))
                    Slider(value: $quality, in: 0.3...1.0)
                    Text("\(Int(quality * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                }
                Picker(L("Risoluzione PDF → immagini"), selection: $pdfDPI) {
                    Text("72 DPI").tag(72.0)
                    Text("150 DPI").tag(150.0)
                    Text("300 DPI").tag(300.0)
                    Text("600 DPI").tag(600.0)
                }
                Toggle(L("Mostra nel Finder al termine"), isOn: $revealAfter)
                Toggle(L("Suono al termine"), isOn: $playSound)
            }
            Section(L("Sistema")) {
                Toggle(L("Apri all'avvio del Mac"), isOn: Binding(get: { sys.launchAtLogin }, set: { v in
                    do {
                        if v { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        sys.launchAtLogin = v
                        sys.loginError = nil
                    } catch {
                        sys.loginError = error.localizedDescription
                    }
                }))
                if let e = sys.loginError { Text(e).font(.caption).foregroundStyle(.red) }
                HStack {
                    Toggle(L("Controlla gli aggiornamenti automaticamente"), isOn: $autoUpdate)
                    Spacer()
                    Button(L("Controlla ora")) { Updater.check(userInitiated: true) }.controlSize(.small)
                }
                HStack {
                    Text("ffmpeg (audio/video)")
                    Spacer()
                    if let p = Shell.ffmpeg {
                        Label(p, systemImage: "checkmark.circle.fill").foregroundStyle(.green).lineLimit(1)
                    } else {
                        Label(L("non trovato"), systemImage: "xmark.circle").foregroundStyle(.secondary)
                        Button(L("Installa…")) { FFmpegInstaller.shared.show() }.controlSize(.small)
                    }
                }
                TextField(L("Percorso ffmpeg personalizzato"), text: $ffmpegPath, prompt: Text(L("automatico")))
                Text(L("Hot key globale: ⌃⌥R apre la ruota sui file selezionati nel Finder."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 660)
    }

    private func keyPicker(_ title: String, _ value: Binding<Int>) -> some View {
        Picker(title, selection: value) {
            ForEach(ModKey.allCases) { k in Text("\(k.glyph)  \(k.name)").tag(k.rawValue) }
        }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    var openSettings: () -> Void
    var close: () -> Void
    @ObservedObject var practice: PracticeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rondo").font(.system(size: 26, weight: .bold))
                    Text(L("Il convertitore di file offline, a portata di trascinamento.")).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                step("1", L("Inizia a trascinare un file"), L("Dal Finder, dalla Scrivania o da qualsiasi app."))
                step("2", L("Premi un tasto mentre trascini"), L("Compare una ruota attorno al cursore. Puoi lasciare il tasto."))
                step("3", L("Rilascia sullo spicchio"), L("Il risultato viene salvato come nuova copia. Al centro = annulla."))
            }
            PracticeCard(model: practice)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                keyRow(.convert, L("formati: immagini, audio, video, PDF, documenti, tabelle, sottotitoli, archivi"))
                keyRow(.tools, L("comprimi, ridimensiona, ruota, scontorna, unisci/dividi PDF, info…"))
                keyRow(.actions, L("AirDrop, Float, copia, sposta, percorso, Terminale"))
            }
            Text(L("Senza trascinare: seleziona i file nel Finder e premi ⌃⌥R. Usa le frecce, Tab per cambiare ruota, Invio per confermare."))
                .font(.callout).foregroundStyle(.secondary)
            if Shell.ffmpeg == nil {
                HStack {
                    Label(L("Per tutti i formati audio e video serve ffmpeg."), systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.orange)
                    Spacer()
                    Button(L("Installa…")) { FFmpegInstaller.shared.show() }.controlSize(.small)
                }
            }
            HStack {
                Button(L("Impostazioni…"), action: openSettings)
                Spacer()
                Button(L("Inizia"), action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func step(_ n: String, _ title: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n).font(.system(size: 13, weight: .bold)).frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor.opacity(0.18)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(sub).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func keyRow(_ kind: WheelKind, _ desc: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Prefs.key(for: kind).glyph).font(.system(size: 15, weight: .bold, design: .rounded))
                .frame(width: 30, height: 24).background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)))
            Text(kind.title).fontWeight(.semibold).frame(width: 80, alignment: .leading)
            Text(desc).font(.callout).foregroundStyle(.secondary)
        }
    }
}
