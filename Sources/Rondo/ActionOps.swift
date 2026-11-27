import AppKit
import AVFoundation
import ImageIO
import PDFKit

// MARK: - File actions (Control wheel)

enum ActionOps {
    static func items() -> [WheelItem] {
        [
            WheelItem(title: "AirDrop", symbol: "dot.radiowaves.left.and.right", mainThread: true, quiet: true) { urls in
                guard let s = NSSharingService(named: .sendViaAirDrop), s.canPerform(withItems: urls) else {
                    throw OpError(L("AirDrop non disponibile"))
                }
                NSApp.activate(ignoringOtherApps: true)
                s.perform(withItems: urls)
                return []
            },
            WheelItem(title: "Float", symbol: "pin", mainThread: true, quiet: true) { urls in
                FloatShelf.shared.add(urls)
                return []
            },
            WheelItem(title: L("Copia"), symbol: "doc.on.doc", mainThread: true, quiet: true,
                      doneMessage: L("Copiato negli appunti")) { urls in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects(urls as [NSURL])
                return []
            },
            WheelItem(title: L("Copia percorso"), symbol: "link", mainThread: true, quiet: true,
                      doneMessage: L("Percorso copiato")) { urls in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
                return []
            },
            WheelItem(title: L("Sposta in…"), symbol: "folder", mainThread: true, quiet: true, doneMessage: L("Spostato")) {
                try transfer($0, move: true)
            },
            WheelItem(title: L("Copia in…"), symbol: "folder.badge.plus", mainThread: true, quiet: true, doneMessage: L("Copiato")) {
                try transfer($0, move: false)
            },
            WheelItem(title: L("Terminale"), symbol: "terminal", mainThread: true, quiet: true) { urls in
                let u = urls[0]
                let dir = FileKinds.isDirectory(u) ? u : u.deletingLastPathComponent()
                guard let term = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
                    throw OpError(L("Terminale non trovato"))
                }
                NSWorkspace.shared.open([dir], withApplicationAt: term, configuration: NSWorkspace.OpenConfiguration())
                return []
            },
            WheelItem(title: L("Mostra nel Finder"), symbol: "magnifyingglass", mainThread: true, quiet: true) { urls in
                NSWorkspace.shared.activateFileViewerSelecting(urls)
                return []
            },
        ]
    }

    static func transfer(_ urls: [URL], move: Bool) throws -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = move ? L("Sposta qui") : L("Copia qui")
        panel.message = move ? L("Scegli dove spostare %d elementi", urls.count) : L("Scegli dove copiare %d elementi", urls.count)
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let dir = panel.url else { return [] }
        return try urls.map { u in
            let ext = FileKinds.isDirectory(u) ? "" : u.pathExtension
            let base = FileKinds.isDirectory(u) ? u.lastPathComponent : u.deletingPathExtension().lastPathComponent
            let dest = Engine.unique(in: dir, base: base, ext: ext)
            if move { try FileManager.default.moveItem(at: u, to: dest) } else { try FileManager.default.copyItem(at: u, to: dest) }
            return dest
        }
    }
}

// MARK: - Info / metadata

enum InfoOps {
    static var item: WheelItem { WheelItem(title: L("Info"), symbol: "info.circle", mainThread: true, quiet: true) { urls in
        alert(L("Informazioni"), urls.prefix(6).map(describe).joined(separator: "\n\n"), copyable: true)
        return []
    } }

    static func alert(_ title: String, _ text: String, copyable: Bool = false) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "OK")
        if copyable { a.addButton(withTitle: L("Copia")) }
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    static func describe(_ u: URL) -> String {
        var lines = [u.lastPathComponent]
        let fm = FileManager.default
        let attrs = (try? fm.attributesOfItem(atPath: u.path)) ?? [:]
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short

        var size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if FileKinds.isDirectory(u), let en = fm.enumerator(at: u, includingPropertiesForKeys: [.fileSizeKey]) {
            size = 0
            var count = 0
            for case let f as URL in en {
                size += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                count += 1
                if count > 50_000 { break }
            }
            lines.append("\(L("Elementi")): \(count)")
        }
        lines.append("\(L("Dimensione")): \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
        if let c = attrs[.creationDate] as? Date { lines.append("\(L("Creato")): \(df.string(from: c))") }
        if let m = attrs[.modificationDate] as? Date { lines.append("\(L("Modificato")): \(df.string(from: m))") }

        switch FileKinds.category(u) {
        case .image:
            if let src = CGImageSourceCreateWithURL(u as CFURL, nil),
               let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
                if let w = p[kCGImagePropertyPixelWidth], let h = p[kCGImagePropertyPixelHeight] { lines.append("\(L("Pixel")): \(w) × \(h)") }
                if let dpi = p[kCGImagePropertyDPIWidth] { lines.append("DPI: \(dpi)") }
                if let cm = p[kCGImagePropertyColorModel] { lines.append("\(L("Colore")): \(cm)") }
                if let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                    let cam = [tiff[kCGImagePropertyTIFFMake], tiff[kCGImagePropertyTIFFModel]].compactMap { $0 as? String }
                    if !cam.isEmpty { lines.append("\(L("Fotocamera")): \(cam.joined(separator: " "))") }
                }
                if let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any], let d = exif[kCGImagePropertyExifDateTimeOriginal] {
                    lines.append("\(L("Scattata")): \(d)")
                }
                if p[kCGImagePropertyGPSDictionary] != nil { lines.append(L("⚠︎ Contiene posizione GPS")) }
            }
        case .pdf:
            if let d = PDFDocument(url: u) {
                lines.append("\(L("Pagine")): \(d.pageCount)")
                let a = d.documentAttributes ?? [:]
                if let t = a[PDFDocumentAttribute.titleAttribute] { lines.append("\(L("Titolo")): \(t)") }
                if let au = a[PDFDocumentAttribute.authorAttribute] { lines.append("\(L("Autore")): \(au)") }
                if d.isEncrypted { lines.append(L("Protetto da password")) }
            }
        case .audio, .video:
            let asset = AVURLAsset(url: u)
            let secs = CMTimeGetSeconds(asset.duration)
            if secs.isFinite, secs > 0 {
                let f = DateComponentsFormatter()
                f.allowedUnits = secs >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
                f.zeroFormattingBehavior = .pad
                lines.append("\(L("Durata")): \(f.string(from: secs) ?? "")")
            }
            if let v = asset.tracks(withMediaType: .video).first {
                let s = v.naturalSize.applying(v.preferredTransform)
                lines.append("Video: \(Int(abs(s.width))) × \(Int(abs(s.height))) · \(Int(v.nominalFrameRate.rounded())) fps")
            }
        default:
            break
        }
        return lines.joined(separator: "\n")
    }
}
