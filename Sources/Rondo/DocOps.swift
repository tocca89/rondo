import AppKit
import PDFKit

enum DocOps {
    static let docTypes: [String: NSAttributedString.DocumentType] = [
        "docx": .officeOpenXML, "doc": .docFormat, "odt": .openDocument, "html": .html, "rtf": .rtf,
    ]

    // MARK: Wheel items

    static func pdfConvertItems() -> [WheelItem] {
        var items: [WheelItem] = ["DOCX": "docx", "TXT": "txt", "Markdown": "md", "RTF": "rtf", "HTML": "html", "ODT": "odt"]
            .sorted { order($0.value) < order($1.value) }
            .map { label, ext in
                WheelItem(title: label, ext: ext, mainThread: true) { urls in
                    try urls.map { u in
                        let out = Engine.output(for: u, ext: ext)
                        try write(try pdfText(u), ext: ext, to: out)
                        return out
                    }
                }
            }
        items.append(WheelItem(title: "PNG", ext: "png") { try $0.flatMap { try renderPages($0, ext: "png", uti: "public.png") } })
        items.append(WheelItem(title: "JPG", ext: "jpg") { try $0.flatMap { try renderPages($0, ext: "jpg", uti: "public.jpeg") } })
        return items
    }

    private static func order(_ ext: String) -> Int {
        ["docx", "pdf", "txt", "md", "rtf", "html", "odt", "doc"].firstIndex(of: ext) ?? 99
    }

    static func docConvertItems() -> [WheelItem] {
        let targets: [(String, String)] = [("DOCX", "docx"), ("PDF", "pdf"), ("TXT", "txt"), ("Markdown", "md"),
                                           ("RTF", "rtf"), ("HTML", "html"), ("ODT", "odt"), ("DOC", "doc")]
        return targets.map { label, ext in
            WheelItem(title: label, ext: ext, mainThread: true) { urls in
                try urls.map { u in
                    let out = Engine.output(for: u, ext: ext)
                    try write(try readDocument(u), ext: ext, to: out)
                    return out
                }
            }
        }
    }

    static func pdfToolItems(count: Int) -> [WheelItem] {
        var items: [WheelItem] = []
        if count > 1 {
            items.append(WheelItem(title: L("Unisci"), symbol: "doc.on.doc") { try [merge($0)] })
        }
        items.append(WheelItem(title: L("Dividi pagine"), symbol: "square.split.2x1") { try $0.map(split) })
        if #available(macOS 14.0, *) {
            items.append(WheelItem(title: L("Comprimi"), symbol: "arrow.down.right.and.arrow.up.left") { try $0.map(compress) })
        }
        items.append(WheelItem(title: L("Ruota pagine"), symbol: "rotate.right") { try $0.map(rotate) })
        items.append(WheelItem(title: L("Prima pagina"), symbol: "photo") { urls in
            try urls.map { u in try renderPages(u, ext: "png", uti: "public.png", onlyFirst: true)[0] }
        })
        return items
    }

    // MARK: Reading

    static func pdfText(_ url: URL) throws -> NSAttributedString {
        guard let doc = PDFDocument(url: url) else { throw OpError(L("Impossibile aprire il PDF")) }
        let s = NSMutableAttributedString()
        for i in 0..<doc.pageCount {
            if let a = doc.page(at: i)?.attributedString {
                s.append(a)
                s.append(NSAttributedString(string: "\n\n"))
            }
        }
        if s.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw OpError(L("Il PDF non contiene testo selezionabile (è una scansione?)"))
        }
        return s
    }

    static func readDocument(_ url: URL) throws -> NSAttributedString {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "md", "markdown":
            let html = Markdown.toHTML(try TextOps.readText(url))
            return try NSAttributedString(data: Data(html.utf8),
                                          options: [.documentType: NSAttributedString.DocumentType.html,
                                                    .characterEncoding: String.Encoding.utf8.rawValue],
                                          documentAttributes: nil)
        case "txt", "text":
            return NSAttributedString(string: try TextOps.readText(url),
                                      attributes: [.font: NSFont.systemFont(ofSize: 12)])
        case "webarchive":
            return try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.webArchive],
                                          documentAttributes: nil)
        default:
            return try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        }
    }

    // MARK: Writing

    static func write(_ s: NSAttributedString, ext: String, to out: URL) throws {
        switch ext {
        case "txt":
            try s.string.write(to: out, atomically: true, encoding: .utf8)
        case "md":
            try Markdown.fromAttributed(s).write(to: out, atomically: true, encoding: .utf8)
        case "pdf":
            try printPDF(s, to: out)
        default:
            guard let type = docTypes[ext] else { throw OpError(L("Formato non supportato")) }
            let r = NSRange(location: 0, length: s.length)
            let data = try s.data(from: r, documentAttributes: [.documentType: type])
            try data.write(to: out)
        }
    }

    static func printPDF(_ s: NSAttributedString, to out: URL) throws {
        let info = NSPrintInfo(dictionary: [NSPrintInfo.AttributeKey.jobSavingURL: out])
        info.jobDisposition = .save
        info.paperSize = NSSize(width: 595, height: 842) // A4
        let m: CGFloat = 56
        info.topMargin = m; info.bottomMargin = m; info.leftMargin = m; info.rightMargin = m
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false

        let width = info.paperSize.width - 2 * m
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        tv.appearance = NSAppearance(named: .aqua)
        tv.drawsBackground = false
        tv.isVerticallyResizable = true
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textStorage?.setAttributedString(s)
        if let lm = tv.layoutManager, let tc = tv.textContainer {
            lm.ensureLayout(for: tc)
            tv.frame.size.height = max(100, lm.usedRect(for: tc).height + 10)
        }
        let op = NSPrintOperation(view: tv, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run() else { throw OpError(L("Creazione PDF non riuscita")) }
    }

    // MARK: PDF operations

    static func renderPages(_ url: URL, ext: String, uti: String, onlyFirst: Bool = false) throws -> [URL] {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { throw OpError(L("Impossibile aprire il PDF")) }
        let scale = Prefs.pdfDPI / 72
        let n = onlyFirst ? 1 : doc.pageCount
        let dir: URL? = n > 1 ? try Engine.newFolder(for: url, suffix: ext.uppercased()) : nil
        let base = url.deletingPathExtension().lastPathComponent
        var outs: [URL] = []
        for i in 0..<n {
            guard let page = doc.page(at: i) else { continue }
            let b = page.bounds(for: .mediaBox)
            var size = b.size
            if page.rotation % 180 != 0 { size = NSSize(width: size.height, height: size.width) }
            let w = Int(size.width * scale), h = Int(size.height * scale)
            let ctx = ImageOps.makeContext(w, h, opaque: true)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx)
            guard let cg = ctx.makeImage() else { continue }
            let out = dir.map { $0.appendingPathComponent(String(format: "%@ %03d.%@", base, i + 1, ext)) }
                ?? Engine.output(for: url, ext: ext, suffix: onlyFirst ? L("pagina 1") : nil)
            try ImageOps.write(cg, to: out, uti: uti, quality: ext == "jpg" ? 0.9 : nil)
            outs.append(out)
        }
        return dir.map { [$0] } ?? outs
    }

    static func merge(_ urls: [URL]) throws -> URL {
        let result = PDFDocument()
        for u in urls {
            guard let d = PDFDocument(url: u) else { throw OpError(L("Impossibile aprire %@", u.lastPathComponent)) }
            for i in 0..<d.pageCount {
                if let p = d.page(at: i)?.copy() as? PDFPage { result.insert(p, at: result.pageCount) }
            }
        }
        let out = Engine.unique(in: Engine.outputDirectory(for: urls[0]), base: L("PDF uniti"), ext: "pdf")
        guard result.write(to: out) else { throw OpError(L("Scrittura PDF non riuscita")) }
        return out
    }

    static func split(_ url: URL) throws -> URL {
        guard let d = PDFDocument(url: url) else { throw OpError(L("Impossibile aprire il PDF")) }
        let dir = try Engine.newFolder(for: url, suffix: L("pagine"))
        let base = url.deletingPathExtension().lastPathComponent
        for i in 0..<d.pageCount {
            guard let p = d.page(at: i)?.copy() as? PDFPage else { continue }
            let single = PDFDocument()
            single.insert(p, at: 0)
            single.write(to: dir.appendingPathComponent(String(format: "%@ %03d.pdf", base, i + 1)))
        }
        return dir
    }

    @available(macOS 14.0, *)
    static func compress(_ url: URL) throws -> URL {
        guard let d = PDFDocument(url: url) else { throw OpError(L("Impossibile aprire il PDF")) }
        let out = Engine.output(for: url, ext: "pdf", suffix: L("compresso"))
        let ok = d.write(to: out, withOptions: [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true])
        guard ok else { throw OpError(L("Compressione non riuscita")) }
        return out
    }

    static func rotate(_ url: URL) throws -> URL {
        guard let d = PDFDocument(url: url) else { throw OpError(L("Impossibile aprire il PDF")) }
        for i in 0..<d.pageCount { if let p = d.page(at: i) { p.rotation = (p.rotation + 90) % 360 } }
        let out = Engine.output(for: url, ext: "pdf", suffix: L("ruotato"))
        guard d.write(to: out) else { throw OpError(L("Scrittura PDF non riuscita")) }
        return out
    }
}

// MARK: - Minimal Markdown <-> rich text

enum Markdown {
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static func replace(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    static func inline(_ s: String) -> String {
        var t = escape(s)
        t = replace(t, "`([^`]+)`", "<code>$1</code>")
        t = replace(t, "\\*\\*(.+?)\\*\\*", "<b>$1</b>")
        t = replace(t, "__(.+?)__", "<b>$1</b>")
        t = replace(t, "(?<![\\w*])\\*(?!\\s)(.+?)\\*(?![\\w*])", "<i>$1</i>")
        t = replace(t, "(?<!\\w)_(?!\\s)(.+?)_(?!\\w)", "<i>$1</i>")
        t = replace(t, "!\\[([^\\]]*)\\]\\(([^)]+)\\)", "$1")
        t = replace(t, "\\[([^\\]]+)\\]\\(([^)]+)\\)", "<a href=\"$2\">$1</a>")
        return t
    }

    static func toHTML(_ md: String) -> String {
        var html = """
        <html><head><meta charset="utf-8"><style>
        body{font-family:-apple-system,Helvetica;font-size:12pt;line-height:1.4}
        code,pre{font-family:Menlo,monospace;font-size:10.5pt} pre{background:#f3f3f3;padding:8px}
        blockquote{color:#555;margin-left:12px}
        </style></head><body>

        """
        var inCode = false
        var list: String?
        var para: [String] = []
        func flushPara() {
            if !para.isEmpty { html += "<p>" + para.map(inline).joined(separator: " ") + "</p>\n"; para = [] }
        }
        func closeList() {
            if let l = list { html += "</\(l)>\n"; list = nil }
        }
        func openList(_ l: String) {
            if list != l { closeList(); html += "<\(l)>\n"; list = l }
        }
        for line in md.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                flushPara(); closeList()
                html += inCode ? "</pre>\n" : "<pre>"
                inCode.toggle()
                continue
            }
            if inCode { html += escape(line) + "\n"; continue }
            if t.isEmpty { flushPara(); closeList(); continue }
            let hashes = t.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), t.dropFirst(hashes).hasPrefix(" ") {
                flushPara(); closeList()
                html += "<h\(hashes)>\(inline(String(t.dropFirst(hashes + 1))))</h\(hashes)>\n"
            } else if ["---", "***", "___"].contains(t) {
                flushPara(); closeList(); html += "<hr>\n"
            } else if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
                flushPara(); openList("ul")
                html += "<li>\(inline(String(t.dropFirst(2))))</li>\n"
            } else if let r = t.range(of: "^\\d+[.)]\\s+", options: .regularExpression) {
                flushPara(); openList("ol")
                html += "<li>\(inline(String(t[r.upperBound...])))</li>\n"
            } else if t.hasPrefix(">") {
                flushPara(); closeList()
                html += "<blockquote>\(inline(String(t.dropFirst()).trimmingCharacters(in: .whitespaces)))</blockquote>\n"
            } else {
                closeList(); para.append(t)
            }
        }
        flushPara(); closeList()
        if inCode { html += "</pre>" }
        return html + "</body></html>"
    }

    static func fromAttributed(_ s: NSAttributedString) -> String {
        var out = ""
        let ns = s.string as NSString
        s.enumerateAttributes(in: NSRange(location: 0, length: s.length)) { attrs, range, _ in
            let text = ns.substring(with: range)
            let traits = (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            var pre = "", post = ""
            if traits.contains(.bold) { pre += "**"; post = "**" + post }
            if traits.contains(.italic) { pre += "*"; post = "*" + post }
            if let link = attrs[.link] {
                let u = (link as? URL)?.absoluteString ?? (link as? String) ?? ""
                pre = "[" + pre
                post += "](\(u))"
            }
            let core = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if pre.isEmpty || core.isEmpty || core.contains("\n") {
                out += text
            } else {
                let lead = String(text.prefix(while: { $0.isWhitespace }))
                let trail = String(text.reversed().prefix(while: { $0.isWhitespace }).reversed())
                out += lead + pre + core + post + trail
            }
        }
        return out
    }
}
