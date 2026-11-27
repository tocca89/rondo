import AppKit

// MARK: - Errors

struct OpError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Preferences

enum ModKey: Int, CaseIterable, Identifiable {
    case shift, command, control, option
    var id: Int { rawValue }
    var flag: NSEvent.ModifierFlags { [.shift, .command, .control, .option][rawValue] }
    var glyph: String { ["⇧", "⌘", "⌃", "⌥"][rawValue] }
    var name: String { ["Shift", "Command", "Control", "Option"][rawValue] }
}

enum OutputMode: Int { case beside, downloads, custom }

enum Prefs {
    static let d = UserDefaults.standard

    static func registerDefaults() {
        d.register(defaults: [
            "convertKey": 0, "toolsKey": 1, "actionsKey": 2,
            "outputMode": 0, "customFolder": "",
            "quality": 0.85, "pdfDPI": 300.0,
            "revealAfter": false, "playSound": true, "enabled": true,
            "ffmpegPath": "", "showWelcome": true,
        ])
    }

    static func key(for kind: WheelKind) -> ModKey {
        ModKey(rawValue: d.integer(forKey: ["convertKey", "toolsKey", "actionsKey"][kind.rawValue])) ?? .shift
    }
    static var outputMode: OutputMode { OutputMode(rawValue: d.integer(forKey: "outputMode")) ?? .beside }
    static var customFolder: String { d.string(forKey: "customFolder") ?? "" }
    static var quality: Double { d.double(forKey: "quality") }
    static var pdfDPI: Double { max(72, d.double(forKey: "pdfDPI")) }
    static var revealAfter: Bool { d.bool(forKey: "revealAfter") }
    static var playSound: Bool { d.bool(forKey: "playSound") }
    static var enabled: Bool {
        get { d.bool(forKey: "enabled") }
        set { d.set(newValue, forKey: "enabled") }
    }
    static var ffmpegPath: String { d.string(forKey: "ffmpegPath") ?? "" }
}

// MARK: - File classification

enum FileCategory { case image, audio, video, pdf, document, table, subtitle, archive, folder, other }

enum FileKinds {
    static let image: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp", "avif",
                                     "svg", "ico", "icns", "jp2", "psd", "dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "tga"]
    static let audio: Set<String> = ["mp3", "m4a", "wav", "flac", "ogg", "oga", "opus", "aiff", "aif", "aifc", "wma", "aac", "caf", "amr"]
    static let video: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi", "wmv", "flv", "mpg", "mpeg", "3gp", "ts", "mts", "m2ts", "ogv"]
    static let document: Set<String> = ["docx", "doc", "rtf", "rtfd", "odt", "html", "htm", "txt", "text", "md", "markdown", "webarchive"]
    static let table: Set<String> = ["csv", "tsv"]
    static let subtitle: Set<String> = ["srt", "vtt"]
    static let archive: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz", "rar", "7z"]

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    static func category(_ url: URL) -> FileCategory {
        let e = url.pathExtension.lowercased()
        if isDirectory(url) { return e == "rtfd" ? .document : .folder }
        if e == "pdf" { return .pdf }
        if image.contains(e) { return .image }
        if audio.contains(e) { return .audio }
        if video.contains(e) { return .video }
        if document.contains(e) { return .document }
        if table.contains(e) { return .table }
        if subtitle.contains(e) { return .subtitle }
        if archive.contains(e) { return .archive }
        return .other
    }

    static func commonCategory(_ urls: [URL]) -> FileCategory? {
        let s = Set(urls.map(category))
        return s.count == 1 ? s.first : nil
    }
}

// MARK: - Output paths

enum Engine {
    static func outputDirectory(for src: URL) -> URL {
        switch Prefs.outputMode {
        case .beside:
            return src.deletingLastPathComponent()
        case .downloads:
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        case .custom:
            let p = Prefs.customFolder
            if p.isEmpty { return src.deletingLastPathComponent() }
            let u = URL(fileURLWithPath: p)
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
            return u
        }
    }

    static func unique(in dir: URL, base: String, ext: String) -> URL {
        func make(_ b: String) -> URL { ext.isEmpty ? dir.appendingPathComponent(b) : dir.appendingPathComponent(b + "." + ext) }
        var u = make(base)
        var n = 2
        while FileManager.default.fileExists(atPath: u.path) {
            u = make("\(base) \(n)")
            n += 1
        }
        return u
    }

    static func baseName(_ src: URL, suffix: String?) -> String {
        var base = FileKinds.isDirectory(src) ? src.lastPathComponent : src.deletingPathExtension().lastPathComponent
        if let s = suffix { base += " (\(s))" }
        return base
    }

    /// New unique file next to the source (or in the configured output folder).
    static func output(for src: URL, ext: String, suffix: String? = nil) -> URL {
        unique(in: outputDirectory(for: src), base: baseName(src, suffix: suffix), ext: ext)
    }

    /// New unique, already-created folder.
    static func newFolder(for src: URL, name: String? = nil, suffix: String? = nil) throws -> URL {
        let u = unique(in: outputDirectory(for: src), base: name ?? baseName(src, suffix: suffix), ext: "")
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func tempDir() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("Rondo-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    // MARK: Running a wheel item

    static func execute(_ item: WheelItem, urls: [URL]) {
        if item.quiet {
            do {
                let outs = try item.run(urls)
                if let m = item.doneMessage { HUD.shared.success(m, urls: outs) }
            } catch {
                HUD.shared.failure(error.localizedDescription)
            }
            return
        }

        let job = Jobs.shared.start(item.title, urls: urls)
        HUD.shared.working("\(item.title)…")
        let work = {
            Thread.current.threadDictionary[Jobs.key] = job
            defer { Thread.current.threadDictionary.removeObject(forKey: Jobs.key) }
            do {
                let outs = try item.run(urls)
                DispatchQueue.main.async {
                    Jobs.shared.finish(job)
                    finish(item, outs)
                    NotificationCenter.default.post(name: .rondoJobFinished, object: nil, userInfo: ["inputs": urls, "outputs": outs])
                }
            } catch {
                DispatchQueue.main.async {
                    Jobs.shared.finish(job)
                    HUD.shared.failure(error.localizedDescription)
                }
            }
        }
        if item.mainThread {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        } else {
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        }
    }

    private static func finish(_ item: WheelItem, _ outs: [URL]) {
        if Prefs.playSound { NSSound(named: "Glass")?.play() }
        let msg: String
        if let m = item.doneMessage { msg = m }
        else if outs.count == 1 { msg = L("Salvato: %@", outs[0].lastPathComponent) }
        else if outs.isEmpty { msg = L("Fatto") }
        else { msg = L("%d file creati", outs.count) }
        HUD.shared.success(msg, urls: outs)
        if Prefs.revealAfter, !outs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(outs) }
    }
}

// MARK: - Shell

enum Shell {
    @discardableResult
    static func run(_ exe: String, _ args: [String], cwd: URL? = nil, env: [String: String]? = nil,
                    onLine: ((String) -> Void)? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        if let env { p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 } }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        try p.run()
        var errData = Data()
        let g = DispatchGroup()
        g.enter()
        DispatchQueue.global().async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            g.leave()
        }
        var outData = Data()
        if let onLine {
            // Stream stdout line by line (used for ffmpeg progress)
            var buffer: [UInt8] = []
            let h = out.fileHandleForReading
            while true {
                let chunk = h.availableData
                if chunk.isEmpty { break }
                outData.append(chunk)
                buffer.append(contentsOf: chunk)
                while let nl = buffer.firstIndex(of: 10) {
                    onLine(String(decoding: buffer[..<nl], as: UTF8.self))
                    buffer.removeSubrange(...nl)
                }
            }
        } else {
            outData = out.fileHandleForReading.readDataToEndOfFile()
        }
        g.wait()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = (String(data: errData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let tool = (exe as NSString).lastPathComponent
            throw OpError(L("%@ ha restituito un errore: %@", tool, String(msg.suffix(280))))
        }
        return String(data: outData, encoding: .utf8) ?? ""
    }

    static var ffmpeg: String? {
        [Prefs.ffmpegPath, "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            .first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
    }
}

// MARK: - Running jobs & progress

final class Jobs {
    static let shared = Jobs()
    static let key = "rondo.job"
    static let changed = Notification.Name("rondoJobsChanged")

    final class Job {
        let title: String
        let urls: [URL]
        var fraction: Double?
        init(title: String, urls: [URL]) { self.title = title; self.urls = urls }
    }

    private(set) var active: [Job] = []

    /// Overall progress of the running jobs (nil = indeterminate).
    var fraction: Double? {
        let known = active.compactMap(\.fraction)
        guard !active.isEmpty, known.count == active.count else { return nil }
        return known.reduce(0, +) / Double(known.count)
    }

    func start(_ title: String, urls: [URL]) -> Job {
        let j = Job(title: title, urls: urls)
        active.append(j)
        NotificationCenter.default.post(name: Jobs.changed, object: nil)
        return j
    }

    func finish(_ job: Job) {
        active.removeAll { $0 === job }
        NotificationCenter.default.post(name: Jobs.changed, object: nil)
    }

    /// Called from worker threads. `input` tells which of the job's files is being processed.
    static func report(input: String?, fraction: Double) {
        guard let job = Thread.current.threadDictionary[key] as? Job else { return }
        let idx = Double(job.urls.firstIndex { $0.path == input } ?? 0)
        let overall = min(1, (idx + max(0, min(1, fraction))) / Double(max(1, job.urls.count)))
        DispatchQueue.main.async {
            job.fraction = overall
            NotificationCenter.default.post(name: Jobs.changed, object: nil)
        }
    }
}
