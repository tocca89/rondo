import AppKit
import CryptoKit
import SwiftUI

/// Guided ffmpeg installation: Homebrew when available, otherwise a direct download
/// of a static Apple-silicon build into Rondo's Application Support folder.
final class FFmpegInstaller: ObservableObject {
    static let shared = FFmpegInstaller()

    enum State: Equatable { case idle, working(String, Double?), done, failed(String) }

    @Published var state: State = .idle
    @Published var lastLine = ""
    private var window: NSWindow?
    private var progressObservation: NSKeyValueObservation?

    static let downloadSource = "ffmpeg.martin-riedl.de"
    static let downloadURL = URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip")!

    static var brewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Where the downloaded binary lives (also searched by `Shell.ffmpeg`).
    static var localBinary: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rondo/bin/ffmpeg")
    }

    var isBusy: Bool { if case .working = state { return true } else { return false } }

    func show() {
        if Shell.ffmpeg != nil, !isBusy { state = .done }
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: FFmpegInstallView(model: self)))
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.title = L("Altri formati audio e video")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    private func set(_ s: State) { DispatchQueue.main.async { self.state = s } }

    private func finished() {
        MediaOps.resetEncoderCache()
        DispatchQueue.main.async {
            self.state = .done
            if Prefs.playSound { NSSound(named: "Glass")?.play() }
        }
    }

    // MARK: Homebrew

    func installWithBrew() {
        guard let brew = Self.brewPath else { return }
        state = .working(L("Installazione con Homebrew…"), nil)
        lastLine = "brew install ffmpeg"
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: brew)
            p.arguments = ["install", "ffmpeg"]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            env["HOMEBREW_NO_ENV_HINTS"] = "1"
            env["NONINTERACTIVE"] = "1"
            p.environment = env
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            p.standardInput = FileHandle.nullDevice
            var tail: [String] = []
            pipe.fileHandleForReading.readabilityHandler = { h in
                let text = String(decoding: h.availableData, as: UTF8.self)
                let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
                guard let last = lines.last else { return }
                tail = Array((tail + lines).suffix(6))
                DispatchQueue.main.async { self.lastLine = last }
            }
            do {
                try p.run()
                p.waitUntilExit()
            } catch {
                self.set(.failed(error.localizedDescription)); return
            }
            pipe.fileHandleForReading.readabilityHandler = nil
            if p.terminationStatus == 0, Shell.ffmpeg != nil {
                self.finished()
            } else {
                self.set(.failed(tail.joined(separator: "\n")))
            }
        }
    }

    // MARK: Direct download

    func download() {
        state = .working(L("Download di ffmpeg…"), 0)
        lastLine = Self.downloadSource
        let task = URLSession.shared.downloadTask(with: Self.downloadURL) { tmp, resp, err in
            guard let tmp, err == nil, (resp as? HTTPURLResponse)?.statusCode == 200, let finalURL = resp?.url else {
                self.set(.failed(err?.localizedDescription ?? L("Download non riuscito")))
                return
            }
            // The temp file disappears when this handler returns: move it first.
            let zip = FileManager.default.temporaryDirectory.appendingPathComponent("rondo-ffmpeg-\(UUID().uuidString).zip")
            do { try FileManager.default.moveItem(at: tmp, to: zip) } catch {
                self.set(.failed(error.localizedDescription)); return
            }
            DispatchQueue.global(qos: .userInitiated).async { self.installZip(zip, from: finalURL) }
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] prog, _ in
            DispatchQueue.main.async {
                if case .working(let t, _) = self?.state { self?.state = .working(t, prog.fractionCompleted) }
            }
        }
        task.resume()
    }

    private func installZip(_ zip: URL, from url: URL) {
        defer { try? FileManager.default.removeItem(at: zip) }
        set(.working(L("Verifica dell'impronta SHA-256…"), nil))
        do {
            // 1. Integrity: compare with the checksum published next to the file
            guard let shaURL = URL(string: url.absoluteString + ".sha256"),
                  let shaText = try? String(contentsOf: shaURL, encoding: .utf8),
                  let expected = shaText.split(separator: " ").first.map({ String($0).lowercased() }),
                  expected.count == 64 else {
                throw OpError(L("Impronta SHA-256 non disponibile"))
            }
            let actual = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else { throw OpError(L("L'impronta SHA-256 non corrisponde: file scartato")) }

            // 2. Unpack and install into Application Support
            set(.working(L("Installazione…"), nil))
            let tmp = try Engine.tempDir()
            defer { try? FileManager.default.removeItem(at: tmp) }
            try Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, tmp.path])
            guard let found = FileManager.default.enumerator(at: tmp, includingPropertiesForKeys: nil)?
                .compactMap({ $0 as? URL }).first(where: { $0.lastPathComponent == "ffmpeg" }) else {
                throw OpError(L("ffmpeg non trovato nell'archivio"))
            }
            let dest = Self.localBinary
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: found, to: dest)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)

            // 3. Smoke test
            let version = try Shell.run(dest.path, ["-hide_banner", "-version"])
            DispatchQueue.main.async { self.lastLine = version.split(separator: "\n").first.map(String.init) ?? "" }
            finished()
        } catch {
            set(.failed(error.localizedDescription))
        }
    }
}

struct FFmpegInstallView: View {
    @ObservedObject var model: FFmpegInstaller

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "film.stack").font(.system(size: 30)).foregroundStyle(Color.accentColor)
                Text(L("Sblocca tutti i formati audio e video")).font(.title3.weight(.bold))
            }
            Text(L("Rondo usa ffmpeg, un componente gratuito e open source, per MP3, OGG, Opus, WebM, MKV, AVI, GIF e per gli strumenti audio e video."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch model.state {
            case .idle, .failed:
                if case .failed(let msg) = model.state {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.callout).lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if FFmpegInstaller.brewPath != nil {
                    choice(L("Installa con Homebrew"), L("Esegue «brew install ffmpeg». Richiede qualche minuto."),
                           primary: true, action: model.installWithBrew)
                }
                choice(L("Scarica ffmpeg (circa 29 MB)"),
                       L("Versione per Apple silicon da %@ (terze parti), verificata con SHA-256 e salvata nella cartella di Rondo.",
                         FFmpegInstaller.downloadSource),
                       primary: FFmpegInstaller.brewPath == nil, action: model.download)
                if FFmpegInstaller.brewPath == nil {
                    Link(L("Preferisci Homebrew? Ecco come installarlo"), destination: URL(string: "https://brew.sh")!)
                        .font(.callout)
                }
            case .working(let title, let fraction):
                HStack(spacing: 12) {
                    ProgressRing(fraction: fraction).frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).fontWeight(.semibold)
                        Text(model.lastLine).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    if let fraction { Spacer(); Text("\(Int(fraction * 100))%").monospacedDigit().foregroundStyle(.secondary) }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
            case .done:
                Label(L("ffmpeg è pronto! I nuovi formati compaiono già nella ruota."), systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green).fontWeight(.semibold)
                HStack { Spacer(); Button(L("Chiudi"), action: model.close).keyboardShortcut(.defaultAction) }
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func choice(_ title: String, _ detail: String, primary: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if primary {
                Button(L("Installa"), action: action).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            } else {
                Button(L("Installa"), action: action)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
}
