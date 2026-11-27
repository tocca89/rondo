import AppKit
import CoreImage
import ImageIO
import PDFKit
import Vision

enum ImageOps {
    struct Target { let label: String; let ext: String; let uti: String }

    static let targets: [Target] = [
        Target(label: "JPG", ext: "jpg", uti: "public.jpeg"),
        Target(label: "PNG", ext: "png", uti: "public.png"),
        Target(label: "HEIC", ext: "heic", uti: "public.heic"),
        Target(label: "WebP", ext: "webp", uti: "org.webmproject.webp"),
        Target(label: "AVIF", ext: "avif", uti: "public.avif"),
        Target(label: "TIFF", ext: "tiff", uti: "public.tiff"),
        Target(label: "GIF", ext: "gif", uti: "com.compuserve.gif"),
        Target(label: "BMP", ext: "bmp", uti: "com.microsoft.bmp"),
    ]

    static var writableTypes: Set<String> {
        Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    }

    // MARK: Wheel items

    static func convertItems() -> [WheelItem] {
        let writable = writableTypes
        var items: [WheelItem] = []
        for t in targets {
            if writable.contains(t.uti) {
                items.append(WheelItem(title: t.label, ext: t.ext) { urls in try urls.map { try convert($0, to: t) } })
            } else if t.ext == "webp", let cwebp = ["/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp"]
                        .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                items.append(WheelItem(title: t.label, ext: t.ext) { urls in
                    try urls.map { u in
                        // cwebp reads PNG/JPG/TIFF; go through a temporary PNG for anything else
                        let tmp = try Engine.tempDir()
                        defer { try? FileManager.default.removeItem(at: tmp) }
                        let png = tmp.appendingPathComponent("in.png")
                        let (cg, _) = try load(u)
                        try write(cg, to: png, uti: "public.png")
                        let out = Engine.output(for: u, ext: "webp")
                        try Shell.run(cwebp, ["-quiet", "-q", String(Int(Prefs.quality * 100)), png.path, "-o", out.path])
                        return out
                    }
                })
            } else if MediaOps.hasEncoder(t.ext == "webp" ? "libwebp" : "libaom-av1") || (t.ext == "avif" && MediaOps.hasEncoder("libsvtav1")) {
                items.append(WheelItem(title: t.label, ext: t.ext) { urls in
                    try urls.map { u in
                        let out = Engine.output(for: u, ext: t.ext)
                        try MediaOps.ff(["-i", u.path, "-frames:v", "1"] + (t.ext == "webp" ? ["-quality", "85"] : []) + [out.path])
                        return out
                    }
                })
            }
        }
        items.append(WheelItem(title: "PDF", ext: "pdf") { urls in try toPDF(urls, merged: false) })
        return items
    }

    static func toolItems(count: Int) -> [WheelItem] {
        var items: [WheelItem] = [
            WheelItem(title: L("Comprimi"), symbol: "arrow.down.right.and.arrow.up.left") { try $0.map(compress) },
            WheelItem(title: L("Riduci 50%"), symbol: "aspectratio") { try $0.map { try transform($0, suffix: "50%") { scale($0, 0.5) } } },
            WheelItem(title: L("Ruota 90°"), symbol: "rotate.right") { try $0.map { try transform($0, suffix: L("ruotata")) { rotateRight($0) } } },
            WheelItem(title: L("Specchia"), symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                try $0.map { try transform($0, suffix: L("specchiata")) { flip($0) } }
            },
            WheelItem(title: L("Bianco e nero"), symbol: "circle.lefthalf.filled") { try $0.map { try transform($0, suffix: L("b&n")) { try grayscale($0) } } },
            WheelItem(title: L("Rimuovi metadati"), symbol: "eye.slash") { try $0.map(stripMetadata) },
        ]
        if #available(macOS 14.0, *) {
            items.insert(WheelItem(title: L("Rimuovi sfondo"), symbol: "person.crop.rectangle") { try $0.map(removeBackground) }, at: 1)
        }
        if count > 1 {
            items.append(WheelItem(title: L("Unisci in PDF"), symbol: "doc.richtext") { try toPDF($0, merged: true) })
        }
        return items
    }

    // MARK: Loading / writing

    static func makeContext(_ w: Int, _ h: Int, opaque: Bool = false) -> CGContext {
        CGContext(data: nil, width: max(1, w), height: max(1, h), bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
    }

    /// Loads the first frame, with EXIF orientation already applied. Returns metadata with orientation reset.
    static func load(_ url: URL) throws -> (CGImage, [CFString: Any]) {
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0 {
            var props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]) ?? [:]
            let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
            let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(w, h, 1),
                kCGImageSourceShouldCacheImmediately: true,
            ]
            if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
                props[kCGImagePropertyOrientation] = 1
                if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                    tiff[kCGImagePropertyTIFFOrientation] = 1
                    props[kCGImagePropertyTIFFDictionary] = tiff
                }
                return (cg, props)
            }
        }
        // Fallback (SVG and other vector formats NSImage understands)
        guard let img = NSImage(contentsOf: url), img.size.width > 0 else {
            throw OpError(L("Impossibile leggere l'immagine %@", url.lastPathComponent))
        }
        let isVector = ["svg", "pdf", "eps"].contains(url.pathExtension.lowercased())
        var px = img.size
        if !isVector, let rep = img.representations.first, rep.pixelsWide > 0 {
            px = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        if isVector {
            let s = max(1, 2048 / max(px.width, px.height))
            px = NSSize(width: px.width * s, height: px.height * s)
        }
        let ctx = makeContext(Int(px.width), Int(px.height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        img.draw(in: NSRect(origin: .zero, size: px))
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = ctx.makeImage() else { throw OpError(L("Impossibile leggere l'immagine")) }
        return (cg, [:])
    }

    static func write(_ cg: CGImage, to url: URL, uti: String, props: [CFString: Any] = [:], quality: Double? = nil) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, uti as CFString, 1, nil) else {
            throw OpError(L("Formato di destinazione non supportato"))
        }
        var p = props
        if let q = quality { p[kCGImageDestinationLossyCompressionQuality] = q }
        CGImageDestinationAddImage(dest, cg, p as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw OpError(L("Scrittura dell'immagine non riuscita")) }
    }

    static func hasAlpha(_ cg: CGImage) -> Bool {
        switch cg.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    static func flatten(_ cg: CGImage) -> CGImage {
        let ctx = makeContext(cg.width, cg.height, opaque: true)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return ctx.makeImage() ?? cg
    }

    static func isLossy(_ ext: String) -> Bool { ["jpg", "heic", "webp", "avif"].contains(ext) }

    /// Target for writing back in the source's own format (PNG if not writable).
    static func sameFormat(_ url: URL) -> Target {
        let e = Catalog.normExt(url.pathExtension)
        if let t = targets.first(where: { $0.ext == e }), writableTypes.contains(t.uti) { return t }
        return targets[1]
    }

    // MARK: Operations

    static func convert(_ url: URL, to t: Target) throws -> URL {
        var (cg, props) = try load(url)
        if ["jpg", "bmp"].contains(t.ext), hasAlpha(cg) { cg = flatten(cg) }
        let out = Engine.output(for: url, ext: t.ext)
        try write(cg, to: out, uti: t.uti, props: props, quality: isLossy(t.ext) ? Prefs.quality : nil)
        return out
    }

    static func transform(_ url: URL, suffix: String, _ f: (CGImage) throws -> CGImage) throws -> URL {
        let (cg, props) = try load(url)
        let t = sameFormat(url)
        var result = try f(cg)
        if t.ext == "jpg", hasAlpha(result) { result = flatten(result) }
        let out = Engine.output(for: url, ext: t.ext, suffix: suffix)
        try write(result, to: out, uti: t.uti, props: props, quality: isLossy(t.ext) ? Prefs.quality : nil)
        return out
    }

    static func compress(_ url: URL) throws -> URL {
        let (cg, props) = try load(url)
        let e = Catalog.normExt(url.pathExtension)
        if e == "heic" {
            let out = Engine.output(for: url, ext: "heic", suffix: L("compressa"))
            try write(cg, to: out, uti: "public.heic", props: props, quality: 0.5)
            return out
        }
        if !hasAlpha(cg) || e == "jpg" {
            var img = flatten(cg)
            let maxSide = max(img.width, img.height)
            if maxSide > 3000 { img = scale(img, 3000 / CGFloat(maxSide)) }
            let out = Engine.output(for: url, ext: "jpg", suffix: L("compressa"))
            try write(img, to: out, uti: "public.jpeg", props: props, quality: 0.6)
            return out
        }
        // Transparent images: keep PNG, limit size.
        let maxSide = max(cg.width, cg.height)
        let img = maxSide > 2048 ? scale(cg, 2048 / CGFloat(maxSide)) : cg
        let out = Engine.output(for: url, ext: "png", suffix: L("compressa"))
        try write(img, to: out, uti: "public.png")
        return out
    }

    static func scale(_ cg: CGImage, _ factor: CGFloat) -> CGImage {
        let w = Int(CGFloat(cg.width) * factor), h = Int(CGFloat(cg.height) * factor)
        let ctx = makeContext(w, h)
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? cg
    }

    static func rotateRight(_ cg: CGImage) -> CGImage {
        let w = cg.width, h = cg.height
        let ctx = makeContext(h, w)
        ctx.translateBy(x: 0, y: CGFloat(w))
        ctx.rotate(by: -.pi / 2)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? cg
    }

    static func flip(_ cg: CGImage) -> CGImage {
        let ctx = makeContext(cg.width, cg.height)
        ctx.translateBy(x: CGFloat(cg.width), y: 0)
        ctx.scaleBy(x: -1, y: 1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return ctx.makeImage() ?? cg
    }

    static func grayscale(_ cg: CGImage) throws -> CGImage {
        let ci = CIImage(cgImage: cg)
        guard let f = CIFilter(name: "CIPhotoEffectMono") else { return cg }
        f.setValue(ci, forKey: kCIInputImageKey)
        guard let o = f.outputImage, let r = CIContext().createCGImage(o, from: ci.extent) else {
            throw OpError(L("Filtro non riuscito"))
        }
        return r
    }

    static func stripMetadata(_ url: URL) throws -> URL {
        let (cg, _) = try load(url)
        let t = sameFormat(url)
        let out = Engine.output(for: url, ext: t.ext, suffix: L("senza metadati"))
        try write(cg, to: out, uti: t.uti, props: [:], quality: isLossy(t.ext) ? Prefs.quality : nil)
        return out
    }

    @available(macOS 14.0, *)
    static func removeBackground(_ url: URL) throws -> URL {
        let (cg, _) = try load(url)
        let req = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg)
        try handler.perform([req])
        guard let obs = req.results?.first, !obs.allInstances.isEmpty else {
            throw OpError(L("Nessun soggetto trovato nell'immagine"))
        }
        let buf = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: false)
        let ci = CIImage(cvPixelBuffer: buf)
        guard let result = CIContext().createCGImage(ci, from: ci.extent) else { throw OpError(L("Scontorno non riuscito")) }
        let out = Engine.output(for: url, ext: "png", suffix: L("senza sfondo"))
        try write(result, to: out, uti: "public.png")
        return out
    }

    static func pdfPage(_ url: URL) throws -> PDFPage {
        let (cg, props) = try load(url)
        var dpi = (props[kCGImagePropertyDPIWidth] as? Double) ?? 72
        if dpi <= 72 { dpi = 150 }
        let size = NSSize(width: Double(cg.width) * 72 / dpi, height: Double(cg.height) * 72 / dpi)
        guard let page = PDFPage(image: NSImage(cgImage: cg, size: size)) else { throw OpError(L("Creazione PDF non riuscita")) }
        return page
    }

    static func toPDF(_ urls: [URL], merged: Bool) throws -> [URL] {
        if merged {
            let doc = PDFDocument()
            for (i, u) in urls.enumerated() { doc.insert(try pdfPage(u), at: i) }
            let out = Engine.unique(in: Engine.outputDirectory(for: urls[0]), base: L("Immagini"), ext: "pdf")
            guard doc.write(to: out) else { throw OpError(L("Scrittura PDF non riuscita")) }
            return [out]
        }
        return try urls.map { u in
            let doc = PDFDocument()
            doc.insert(try pdfPage(u), at: 0)
            let out = Engine.output(for: u, ext: "pdf")
            guard doc.write(to: out) else { throw OpError(L("Scrittura PDF non riuscita")) }
            return out
        }
    }
}
