import AppKit
import SwiftUI

// MARK: - Interactive practice for the welcome window

/// Follows the user through their first conversion: drag the demo image → press the key → drop on a slice.
final class PracticeModel: ObservableObject {
    enum Step { case waiting, dragging, wheel, done }

    @Published var step: Step = .waiting
    @Published var output: URL?
    let demo: URL
    private var observers: [Any] = []

    init() {
        demo = PracticeModel.makeDemoImage()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .rondoDragStarted, object: nil, queue: .main) { [weak self] n in
            guard let self, self.step != .done, let urls = n.object as? [URL], urls.contains(where: { $0.path == self.demo.path })
            else { return }
            self.step = .dragging
        })
        observers.append(nc.addObserver(forName: .rondoWheelShown, object: nil, queue: .main) { [weak self] _ in
            if self?.step == .dragging { self?.step = .wheel }
        })
        observers.append(nc.addObserver(forName: .rondoJobFinished, object: nil, queue: .main) { [weak self] n in
            guard let self, let inputs = n.userInfo?["inputs"] as? [URL], inputs.contains(where: { $0.path == self.demo.path })
            else { return }
            self.output = (n.userInfo?["outputs"] as? [URL])?.first
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { self.step = .done }
        })
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    /// A colorful sample picture in Application Support, recreated if missing.
    static func makeDemoImage() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rondo/Demo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Rondo-demo.png")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        let w = 1200, h = 800
        let ctx = ImageOps.makeContext(w, h, opaque: true)
        let colors = [CGColor(srgbRed: 0.20, green: 0.85, blue: 0.92, alpha: 1),
                      CGColor(srgbRed: 0.42, green: 0.39, blue: 1.00, alpha: 1),
                      CGColor(srgbRed: 1.00, green: 0.36, blue: 0.63, alpha: 1)]
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 0.55, 1]) {
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: w, y: h), options: [])
        }
        // Concentric "rondo" rings
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.35))
        for i in 1...6 {
            let r = CGFloat(i) * 70
            ctx.setLineWidth(CGFloat(14 - i))
            ctx.strokeEllipse(in: CGRect(x: CGFloat(w) / 2 - r, y: CGFloat(h) / 2 - r, width: r * 2, height: r * 2))
        }
        if let cg = ctx.makeImage() { try? ImageOps.write(cg, to: url, uti: "public.png") }
        return url
    }
}

struct PracticeCard: View {
    @ObservedObject var model: PracticeModel

    private var key: String { Prefs.key(for: .convert).glyph }

    var body: some View {
        HStack(spacing: 16) {
            DraggableFile(url: model.demo)
                .frame(width: 96, height: 72)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.25)))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Prova adesso")).font(.headline)
                Group {
                    switch model.step {
                    case .waiting:
                        Text(L("Trascina questa immagine e, mentre la tieni, premi %@", key))
                    case .dragging:
                        Label(L("Ora premi %@", key), systemImage: "keyboard").foregroundStyle(Color.accentColor)
                    case .wheel:
                        Label(L("Rilascia su uno spicchio, ad esempio JPG"), systemImage: "hand.point.up.left")
                            .foregroundStyle(Color.accentColor)
                    case .done:
                        HStack(spacing: 8) {
                            Label(L("Ce l'hai fatta! Hai creato %@", model.output?.lastPathComponent ?? ""),
                                  systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            if let out = model.output {
                                Button(L("Mostra")) { NSWorkspace.shared.activateFileViewerSelecting([out]) }
                                    .controlSize(.small)
                            }
                        }
                    }
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: model.step)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(model.step == .done ? 0.06 : 0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.accentColor.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: model.step == .done ? [] : [6, 4])))
    }
}

/// AppKit drag source: writes a real file URL to the drag pasteboard (SwiftUI's onDrag writes it lazily).
struct DraggableFile: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> DragSourceView { DragSourceView(url: url) }
    func updateNSView(_ v: DragSourceView, context: Context) {}
}

final class DragSourceView: NSView, NSDraggingSource {
    let url: URL
    private let image: NSImage?

    init(url: URL) {
        self.url = url
        image = NSImage(contentsOf: url)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDragged(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
