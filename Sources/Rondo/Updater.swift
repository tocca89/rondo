import AppKit
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
                let dmg = assets.compactMap { $0["browser_download_url"] as? String }.first { $0.hasSuffix(".dmg") }
                result = .success(Release(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
                                          notes: json["body"] as? String ?? "",
                                          pageURL: page, downloadURL: dmg.flatMap(URL.init(string:))))
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
        a.addButton(withTitle: L("Scarica"))
        a.addButton(withTitle: L("Più tardi"))
        a.addButton(withTitle: L("Salta questa versione"))
        NSApp.activate(ignoringOtherApps: true)
        switch a.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(r.downloadURL ?? r.pageURL)
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
