import AppKit
import CryptoKit
import SwiftUI

// MARK: - Update checks (GitHub Releases, no dependencies)

enum Updater {
    static let repo = "tocca89/rondo"
    static let repoURL = URL(string: "https://github.com/\(repo)")!
    static let creatorName = "tocca89"
    static let creatorURL = URL(string: "https://github.com/tocca89")!

    struct Release {
        let version: String
        let notes: String
        let pageURL: URL
        let downloadURL: URL?
        let signatureURL: URL?
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Semantic-ish comparison: "1.10.0" > "1.9.2", leading "v" ignored.
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    static func fetchLatest(_ done: @escaping (Result<Release, Error>) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Rondo-Updater", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let result: Result<Release, Error>
            if let err {
                result = .failure(err)
            } else if let data, (resp as? HTTPURLResponse)?.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String,
                      let page = (json["html_url"] as? String).flatMap(URL.init(string:)) {
                let assets = json["assets"] as? [[String: Any]] ?? []
                let links = assets.compactMap { $0["browser_download_url"] as? String }
                let dmg = links.first { $0.hasSuffix(".dmg") }
                let sig = dmg.flatMap { d in links.first { $0 == d + ".sig" } }
                result = .success(Release(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
                                          notes: json["body"] as? String ?? "",
                                          pageURL: page, downloadURL: dmg.flatMap(URL.init(string:)),
                                          signatureURL: sig.flatMap(URL.init(string:))))
            } else {
                result = .failure(OpError("HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)"))
            }
            DispatchQueue.main.async { done(result) }
        }.resume()
    }

    /// userInitiated: always report the outcome. Automatic checks stay silent unless there is something new.
    static func check(userInitiated: Bool) {
        Prefs.d.set(Date(), forKey: "lastUpdateCheck")
        fetchLatest { result in
            switch result {
            case .success(let r) where isNewer(r.version, than: currentVersion):
                if !userInitiated, Prefs.d.string(forKey: "skippedVersion") == r.version { return }
                offer(r)
            case .success:
                if userInitiated {
                    InfoOps.alert(L("Rondo è aggiornato"), L("Stai usando l'ultima versione (%@).", currentVersion))
                }
            case .failure(let e):
                if userInitiated { InfoOps.alert(L("Impossibile controllare gli aggiornamenti"), e.localizedDescription) }
            }
        }
    }

    private static func offer(_ r: Release) {
        var notes = r.notes
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "### ", with: "")
            .replacingOccurrences(of: "\r", with: "")
        if notes.count > 700 { notes = String(notes.prefix(700)) + "…" }
        let a = NSAlert()
        a.messageText = L("È disponibile Rondo %@", r.version)
        a.informativeText = L("Hai la versione %@.", currentVersion) + (notes.isEmpty ? "" : "\n\n" + notes)
        let automatic = r.downloadURL != nil && r.signatureURL != nil && AutoInstaller.canInstallInPlace()
        a.addButton(withTitle: automatic ? L("Installa e riavvia") : L("Scarica"))
        a.addButton(withTitle: L("Più tardi"))
        a.addButton(withTitle: L("Salta questa versione"))
        NSApp.activate(ignoringOtherApps: true)
        switch a.runModal() {
        case .alertFirstButtonReturn:
            if automatic { AutoInstaller.installInteractively(r) } else { NSWorkspace.shared.open(r.downloadURL ?? r.pageURL) }
        case .alertThirdButtonReturn: Prefs.d.set(r.version, forKey: "skippedVersion")
        default: break
        }
    }

    private static var timer: Timer?

    /// Checks shortly after launch and then at most once a day, if enabled in Settings.
    static func startAutomaticChecks() {
        let tick = {
            guard Prefs.d.bool(forKey: "autoUpdate") else { return }
            let last = Prefs.d.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
            if Date().timeIntervalSince(last) > 24 * 3600 { check(userInitiated: false) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: tick)
        let t = Timer(timeInterval: 3 * 3600, repeats: true) { _ in tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

// MARK: - Automatic install

/// Downloads a release DMG, checks its Ed25519 signature against the key built into the app,
/// swaps the app bundle in place (old copy goes to the Trash) and relaunches.
enum AutoInstaller {
    /// Public half of the key created by Scripts/update_keygen.swift. Only DMGs signed with its private half are installed.
    static let publicKeyBase64 = "cVmfZgQ+wedpxCtZEQ/95T7eiLblYZt5LEOZvR0ayeg="

    static func canInstallInPlace(_ app: URL = Bundle.main.bundleURL) -> Bool {
        let fm = FileManager.default
        guard app.pathExtension == "app", !app.path.contains("/AppTranslocation/"), !app.path.hasPrefix("/Volumes/") else { return false }
        return fm.isWritableFile(atPath: app.deletingLastPathComponent().path) && fm.isWritableFile(atPath: app.path)
    }

    static func verify(_ data: Data, signature: String) -> Bool {
        guard let keyData = Data(base64Encoded: publicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let sig = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return key.isValidSignature(sig, for: data)
    }

    /// Menu/alert entry point: progress in the HUD, errors offer the manual DMG.
    static func installInteractively(_ r: Updater.Release) {
        let title = L("Aggiornamento a Rondo %@…", r.version)
        let job = Jobs.shared.start(title, urls: [])
        HUD.shared.working(title)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try install(r, app: Bundle.main.bundleURL) { f in
                    DispatchQueue.main.async {
                        job.fraction = f
                        NotificationCenter.default.post(name: Jobs.changed, object: nil)
                    }
                }
                DispatchQueue.main.async {
                    Jobs.shared.finish(job)
                    relaunch(Bundle.main.bundleURL)
                }
            } catch {
                DispatchQueue.main.async {
                    Jobs.shared.finish(job)
                    HUD.shared.failure(error.localizedDescription)
                    let a = NSAlert()
                    a.messageText = L("Aggiornamento automatico non riuscito")
                    a.informativeText = error.localizedDescription
                    a.addButton(withTitle: L("Scarica il DMG"))
                    a.addButton(withTitle: L("Chiudi"))
                    NSApp.activate(ignoringOtherApps: true)
                    if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(r.downloadURL ?? r.pageURL) }
                }
            }
        }
    }

    /// Synchronous; call off the main thread. Leaves `app` replaced by the new version.
    static func install(_ r: Updater.Release, app: URL, progress: @escaping (Double?) -> Void) throws {
        guard let dmgURL = r.downloadURL, let sigURL = r.signatureURL else { throw OpError(L("Il pacchetto di aggiornamento non è valido")) }
        let fm = FileManager.default

        // 1. Download + signature check
        let dmg = try download(dmgURL, progress: { progress($0 * 0.85) })
        defer { try? fm.removeItem(at: dmg) }
        progress(nil)
        let signature = try String(contentsOf: sigURL, encoding: .utf8)
        guard verify(try Data(contentsOf: dmg), signature: signature) else {
            throw OpError(L("Firma dell'aggiornamento non valida: installazione annullata"))
        }

        // 2. Mount and sanity-check the new bundle
        let mountRoot = try Engine.tempDir()
        defer { try? fm.removeItem(at: mountRoot) }
        let plist = try Shell.run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen",
                                                       "-mountrandom", mountRoot.path, "-plist"])
        guard let info = try? PropertyListSerialization.propertyList(from: Data(plist.utf8), format: nil) as? [String: Any],
              let mount = (info["system-entities"] as? [[String: Any]])?.compactMap({ $0["mount-point"] as? String }).first else {
            throw OpError(L("Il pacchetto di aggiornamento non è valido"))
        }
        defer { _ = try? Shell.run("/usr/bin/hdiutil", ["detach", mount, "-force"]) }
        let newApp = URL(fileURLWithPath: mount).appendingPathComponent(app.lastPathComponent)
        let newInfo = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        let oldInfo = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        guard let newID = newInfo["CFBundleIdentifier"] as? String, newID == oldInfo["CFBundleIdentifier"] as? String,
              let newVersion = newInfo["CFBundleShortVersionString"] as? String,
              Updater.isNewer(newVersion, than: oldInfo["CFBundleShortVersionString"] as? String ?? "0") else {
            throw OpError(L("Il pacchetto di aggiornamento non è valido"))
        }

        // 3. Stage next to the app (same volume → atomic rename), then swap
        let stage = app.deletingLastPathComponent().appendingPathComponent(".Rondo-update-\(UUID().uuidString).app")
        try Shell.run("/usr/bin/ditto", [newApp.path, stage.path])
        progress(0.95)
        var trashed: NSURL?
        do {
            try fm.trashItem(at: app, resultingItemURL: &trashed)
            try fm.moveItem(at: stage, to: app)
        } catch {
            // Roll back: put the old app back if it was already moved away
            if !fm.fileExists(atPath: app.path), let t = trashed as URL? { try? fm.moveItem(at: t, to: app) }
            try? fm.removeItem(at: stage)
            throw error
        }
        progress(1)
    }

    /// Waits for this process to quit, then opens the (new) app.
    static func relaunch(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"",
                       "sh", String(ProcessInfo.processInfo.processIdentifier), app.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    private static func download(_ url: URL, progress: @escaping (Double) -> Void) throws -> URL {
        let sem = DispatchSemaphore(value: 0)
        var result: Result<URL, Error> = .failure(OpError(L("Download non riuscito")))
        let task = URLSession.shared.downloadTask(with: url) { tmp, resp, err in
            let okStatus = (resp as? HTTPURLResponse).map { $0.statusCode == 200 } ?? true // file:// in tests
            if let tmp, err == nil, okStatus {
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent("rondo-update-\(UUID().uuidString).dmg")
                do { try FileManager.default.moveItem(at: tmp, to: dest); result = .success(dest) } catch { result = .failure(error) }
            } else if let err {
                result = .failure(err)
            }
            sem.signal()
        }
        let obs = task.progress.observe(\.fractionCompleted) { p, _ in progress(p.fractionCompleted) }
        task.resume()
        sem.wait()
        obs.invalidate()
        return try result.get()
    }
}

// MARK: - About window

struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Rondo").font(.system(size: 26, weight: .bold))
            Text(L("Trascina. Tocca. Fatto.")).foregroundStyle(.secondary)
            Text(L("Versione %@", Updater.currentVersion)).font(.callout).foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Text(L("Creato da"))
                Link("@\(Updater.creatorName)", destination: Updater.creatorURL).fontWeight(.semibold)
            }
            .padding(.top, 6)

            HStack(spacing: 10) {
                Link(L("Codice sorgente"), destination: Updater.repoURL)
                Text("·").foregroundStyle(.tertiary)
                Link(L("Segnala un problema"), destination: Updater.repoURL.appendingPathComponent("issues"))
            }
            .font(.callout)

            Button(L("Controlla aggiornamenti…")) { Updater.check(userInitiated: true) }
                .padding(.top, 6)

            Text(L("Software libero con licenza MIT")).font(.caption).foregroundStyle(.tertiary).padding(.top, 4)
        }
        .padding(28)
        .frame(width: 340)
    }
}
