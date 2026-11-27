import AppKit

// MARK: - Tables & subtitles

enum TextOps {
    static func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        var s = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        if s.hasPrefix("\u{FEFF}") { s.removeFirst() }
        return s
    }

    // MARK: Delimited text

    static func separator(for url: URL, text: String) -> Character {
        if url.pathExtension.lowercased() == "tsv" { return "\t" }
        let first = text.prefix(while: { $0 != "\n" && $0 != "\r\n" })
        if first.filter({ $0 == "\t" }).count > first.filter({ $0 == "," }).count { return "\t" }
        return first.filter({ $0 == ";" }).count > first.filter({ $0 == "," }).count ? ";" : ","
    }

    static func parse(_ text: String, sep: Character) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else { field.append(c) }
            } else if c == "\"" {
                inQuotes = true
            } else if c == sep {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field); field = ""
                rows.append(row); row = []
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    static func serialize(_ rows: [[String]], sep: Character) -> String {
        rows.map { row in
            row.map { f in
                f.contains(sep) || f.contains("\"") || f.contains("\n") || f.contains("\r")
                    ? "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : f
            }.joined(separator: String(sep))
        }.joined(separator: "\n") + "\n"
    }

    static func jsonString(_ s: String) -> String {
        (try? JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    static func toJSON(_ rows: [[String]]) -> String {
        guard let header = rows.first else { return "[]\n" }
        let objects = rows.dropFirst().map { row -> String in
            let pairs = header.enumerated().map { i, k in "\(jsonString(k)): \(jsonString(i < row.count ? row[i] : ""))" }
            return "  {" + pairs.joined(separator: ", ") + "}"
        }
        return "[\n" + objects.joined(separator: ",\n") + "\n]\n"
    }

    static func toHTML(_ rows: [[String]]) -> String {
        var h = "<!doctype html><meta charset=\"utf-8\"><style>table{border-collapse:collapse;font-family:-apple-system,sans-serif}"
            + "td,th{border:1px solid #ccc;padding:4px 8px}th{background:#f2f2f2}</style><table>\n"
        for (i, r) in rows.enumerated() {
            let tag = i == 0 ? "th" : "td"
            h += "<tr>" + r.map { "<\(tag)>\(Markdown.escape($0))</\(tag)>" }.joined() + "</tr>\n"
        }
        return h + "</table>\n"
    }

    static func toMarkdown(_ rows: [[String]]) -> String {
        guard let header = rows.first else { return "" }
        let n = rows.map(\.count).max() ?? header.count
        func line(_ r: [String]) -> String {
            "| " + (0..<n).map { i in (i < r.count ? r[i] : "").replacingOccurrences(of: "|", with: "\\|") }.joined(separator: " | ") + " |"
        }
        var out = [line(header), "|" + Array(repeating: " --- |", count: n).joined()]
        out += rows.dropFirst().map(line)
        return out.joined(separator: "\n") + "\n"
    }

    static func tableItems() -> [WheelItem] {
        let targets: [(String, String, ([[String]]) -> String)] = [
            ("CSV", "csv", { serialize($0, sep: ",") }),
            ("TSV", "tsv", { serialize($0, sep: "\t") }),
            ("JSON", "json", toJSON),
            ("HTML", "html", toHTML),
            ("Markdown", "md", toMarkdown),
        ]
        return targets.map { label, ext, f in
            WheelItem(title: label, ext: ext) { urls in
                try urls.map { u in
                    let text = try readText(u)
                    let rows = parse(text, sep: separator(for: u, text: text))
                    let out = Engine.output(for: u, ext: ext, suffix: ext == u.pathExtension.lowercased() ? L("convertito") : nil)
                    try f(rows).write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            }
        }
    }

    // MARK: Subtitles

    static func blocks(_ text: String) -> [[String]] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
            .filter { !$0.isEmpty }
    }

    static func srtToVtt(_ text: String) -> String {
        var out = "WEBVTT\n\n"
        for b in blocks(text) {
            guard let ti = b.firstIndex(where: { $0.contains("-->") }) else { continue }
            out += Markdown.replace(b[ti], "(\\d{2}:\\d{2}:\\d{2}),(\\d{3})", "$1.$2") + "\n"
            out += b[(ti + 1)...].joined(separator: "\n") + "\n\n"
        }
        return out
    }

    static func vttTime(_ t: String) -> String {
        var s = t.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: ",")
        if s.split(separator: ":").count == 2 { s = "00:" + s }
        return s
    }

    static func vttToSrt(_ text: String) -> String {
        var out = ""
        var n = 1
        for b in blocks(text) {
            guard let ti = b.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = b[ti].components(separatedBy: "-->")
            let start = vttTime(parts[0])
            let end = vttTime(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ")[0])
            out += "\(n)\n\(start) --> \(end)\n" + b[(ti + 1)...].joined(separator: "\n") + "\n\n"
            n += 1
        }
        return out
    }

    static func subtitleText(_ text: String) -> String {
        blocks(text).compactMap { b -> String? in
            guard let ti = b.firstIndex(where: { $0.contains("-->") }) else { return nil }
            return Markdown.replace(b[(ti + 1)...].joined(separator: " "), "<[^>]+>", "")
        }.joined(separator: "\n") + "\n"
    }

    static func subtitleItems() -> [WheelItem] {
        let targets: [(String, String)] = [("SRT", "srt"), ("VTT", "vtt"), ("TXT", "txt")]
        return targets.map { label, ext in
            WheelItem(title: label, ext: ext) { urls in
                try urls.map { u in
                    let text = try readText(u)
                    let isVtt = u.pathExtension.lowercased() == "vtt"
                    let result: String
                    switch ext {
                    case "srt": result = isVtt ? vttToSrt(text) : text
                    case "vtt": result = isVtt ? text : srtToVtt(text)
                    default: result = subtitleText(text)
                    }
                    let out = Engine.output(for: u, ext: ext)
                    try result.write(to: out, atomically: true, encoding: .utf8)
                    return out
                }
            }
        }
    }

    // MARK: Word count

    static var wordCountItem: WheelItem { WheelItem(title: L("Conta parole"), symbol: "textformat.123", mainThread: true, quiet: true) { urls in
        var lines: [String] = []
        for u in urls.prefix(10) {
            let text: String
            switch FileKinds.category(u) {
            case .document: text = (try? DocOps.readDocument(u).string) ?? ""
            default: text = (try? readText(u)) ?? ""
            }
            var words = 0
            text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in words += 1 }
            let lineCount = text.components(separatedBy: .newlines).count
            lines.append(u.lastPathComponent + "\n" + L("%d parole · %d caratteri · %d righe", words, text.count, lineCount))
        }
        InfoOps.alert(L("Conteggio"), lines.joined(separator: "\n\n"))
        return []
    } }
}

// MARK: - Archives

enum ArchiveOps {
    static let multiSuffixes = [".tar.gz", ".tar.bz2", ".tar.xz", ".tgz", ".tbz", ".txz", ".tar", ".zip", ".rar", ".7z", ".gz", ".bz2", ".xz"]

    static func baseName(_ u: URL) -> String {
        let n = u.lastPathComponent
        for suf in multiSuffixes where n.lowercased().hasSuffix(suf) { return String(n.dropLast(suf.count)) }
        return u.deletingPathExtension().lastPathComponent
    }

    static func isTarLike(_ n: String) -> Bool {
        [".tar", ".tar.gz", ".tgz", ".tar.bz2", ".tbz", ".tar.xz", ".txz", ".rar", ".7z"].contains { n.hasSuffix($0) }
    }

    /// Extracts into `dir` (or a new folder next to the archive). Returns the output folder/file.
    @discardableResult
    static func extract(_ u: URL, into dir: URL? = nil) throws -> URL {
        let n = u.lastPathComponent.lowercased()
        if !isTarLike(n), n.hasSuffix(".gz") || n.hasSuffix(".bz2") || n.hasSuffix(".xz") {
            let tool = n.hasSuffix(".gz") ? "gzip" : n.hasSuffix(".bz2") ? "bzip2" : "xz"
            let out = dir.map { $0.appendingPathComponent(baseName(u)) }
                ?? Engine.unique(in: Engine.outputDirectory(for: u), base: baseName(u), ext: "")
            try Shell.run("/bin/sh", ["-c", "\(tool) -dc \"$1\" > \"$2\"", "sh", u.path, out.path],
                          env: ["PATH": "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin"])
            return out
        }
        let target = try dir ?? Engine.newFolder(for: u, name: baseName(u))
        if n.hasSuffix(".zip") {
            try Shell.run("/usr/bin/ditto", ["-x", "-k", u.path, target.path])
        } else {
            try Shell.run("/usr/bin/tar", ["-xf", u.path, "-C", target.path])
        }
        return target
    }

    static func repack(_ u: URL, zip: Bool) throws -> URL {
        let tmp = try Engine.tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try extract(u, into: tmp)
        let out = Engine.unique(in: Engine.outputDirectory(for: u), base: baseName(u), ext: zip ? "zip" : "tar.gz")
        if zip {
            try Shell.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", tmp.path, out.path])
        } else {
            try Shell.run("/usr/bin/tar", ["-czf", out.path, "-C", tmp.path, "."], env: ["COPYFILE_DISABLE": "1"])
        }
        return out
    }

    static func pack(_ urls: [URL], zip: Bool) throws -> URL {
        let first = urls[0]
        let name = urls.count == 1 ? Engine.baseName(first, suffix: nil) : L("Archivio")
        let out = Engine.unique(in: Engine.outputDirectory(for: first), base: name, ext: zip ? "zip" : "tar.gz")
        let parent = first.deletingLastPathComponent()
        let sameParent = Set(urls.map { $0.deletingLastPathComponent().path }).count == 1
        let names = sameParent ? urls.map(\.lastPathComponent) : urls.map(\.path)
        if zip {
            if urls.count == 1 {
                try Shell.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, out.path])
            } else {
                try Shell.run("/usr/bin/zip", ["-r", "-y", "-q", out.path] + names + ["-x", "*.DS_Store"],
                              cwd: sameParent ? parent : nil)
            }
        } else {
            try Shell.run("/usr/bin/tar", ["-czf", out.path] + (sameParent ? ["-C", parent.path] : []) + names,
                          env: ["COPYFILE_DISABLE": "1"])
        }
        return out
    }

    static var zipItem: WheelItem { WheelItem(title: "ZIP", symbol: "doc.zipper") { [try pack($0, zip: true)] } }
    static var tarItem: WheelItem { WheelItem(title: "TAR.GZ", symbol: "archivebox") { [try pack($0, zip: false)] } }

    static func convertItems() -> [WheelItem] {
        [
            WheelItem(title: L("Estrai"), symbol: "arrow.up.bin") { try $0.map { try extract($0) } },
            WheelItem(title: "ZIP", ext: "zip") { try $0.map { try repack($0, zip: true) } },
            WheelItem(title: "TAR.GZ", ext: "tgz") { try $0.map { try repack($0, zip: false) } },
        ]
    }
}
