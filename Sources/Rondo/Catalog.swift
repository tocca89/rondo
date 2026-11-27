import AppKit

enum WheelKind: Int, CaseIterable {
    case convert, tools, actions

    var title: String { [L("Converti"), L("Strumenti"), L("Azioni")][rawValue] }
    var symbol: String { ["arrow.triangle.2.circlepath", "wrench.and.screwdriver", "bolt"][rawValue] }
    var next: WheelKind { WheelKind(rawValue: (rawValue + 1) % 3)! }
}

struct WheelItem {
    var title: String
    /// SF Symbol name. Empty = draw the title big (used for format names like "PNG").
    var symbol: String = ""
    /// Output extension, used to hide "convert to the same format".
    var ext: String? = nil
    var mainThread: Bool = false
    /// Quiet items (file actions) run immediately on the main thread without progress HUD.
    var quiet: Bool = false
    var doneMessage: String? = nil
    var run: ([URL]) throws -> [URL]
}

enum Catalog {
    static func items(_ kind: WheelKind, for urls: [URL]) -> [WheelItem] {
        guard !urls.isEmpty else { return [] }
        switch kind {
        case .convert: return filterSameFormat(convertItems(urls), urls) + ffmpegOffer(urls)
        case .tools: return toolItems(urls)
        case .actions: return ActionOps.items()
        }
    }

    static func normExt(_ e: String) -> String {
        let e = e.lowercased()
        return ["jpeg": "jpg", "tif": "tiff", "htm": "html", "aif": "aiff", "markdown": "md", "heif": "heic", "text": "txt"][e] ?? e
    }

    private static func filterSameFormat(_ items: [WheelItem], _ urls: [URL]) -> [WheelItem] {
        let exts = Set(urls.map { normExt($0.pathExtension) })
        guard exts.count == 1, let e = exts.first else { return items }
        return items.filter { $0.ext.map(normExt) != e }
    }

    /// "More formats…" slice for audio/video when ffmpeg is missing: opens the guided installer.
    private static func ffmpegOffer(_ urls: [URL]) -> [WheelItem] {
        guard Shell.ffmpeg == nil, let cat = FileKinds.commonCategory(urls), cat == .audio || cat == .video else { return [] }
        return [WheelItem(title: L("Altri formati…"), symbol: "plus.circle", mainThread: true, quiet: true) { _ in
            FFmpegInstaller.shared.show()
            return []
        }]
    }

    private static func convertItems(_ urls: [URL]) -> [WheelItem] {
        switch FileKinds.commonCategory(urls) {
        case .image: return ImageOps.convertItems()
        case .audio: return MediaOps.audioConvertItems()
        case .video: return MediaOps.videoConvertItems()
        case .pdf: return DocOps.pdfConvertItems()
        case .document: return DocOps.docConvertItems()
        case .table: return TextOps.tableItems()
        case .subtitle: return TextOps.subtitleItems()
        case .archive: return ArchiveOps.convertItems()
        case .folder: return [ArchiveOps.zipItem, ArchiveOps.tarItem]
        default: return []
        }
    }

    private static func toolItems(_ urls: [URL]) -> [WheelItem] {
        var items: [WheelItem]
        switch FileKinds.commonCategory(urls) {
        case .image: items = ImageOps.toolItems(count: urls.count)
        case .pdf: items = DocOps.pdfToolItems(count: urls.count)
        case .video: items = MediaOps.videoToolItems()
        case .audio: items = MediaOps.audioToolItems()
        case .document, .table, .subtitle: items = [TextOps.wordCountItem]
        default: items = []
        }
        items += ffmpegOffer(urls)
        items.append(ArchiveOps.zipItem)
        if items.count < 3 { items.append(ArchiveOps.tarItem) }
        items.append(InfoOps.item)
        return items
    }
}
