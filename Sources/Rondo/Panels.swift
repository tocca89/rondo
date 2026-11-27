import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - HUD

final class HUD {
    static let shared = HUD()

    enum State { case idle, working(String, Double?), success(String), failure(String) }
    final class Model: ObservableObject { @Published var state: State = .idle }

    private let model = Model()
    private var panel: NSPanel?
    private var outputs: [URL] = []
    private var hideWork: DispatchWorkItem?

    private var workingTitle = ""
    private var observer: Any?

    func working(_ t: String) {
        workingTitle = t
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: Jobs.changed, object: nil, queue: .main) { [weak self] _ in
                guard let self, case .working = self.model.state, !Jobs.shared.active.isEmpty else { return }
                let n = Jobs.shared.active.count
                self.model.state = .working(n > 1 ? "\(self.workingTitle) (+\(n - 1))" : self.workingTitle, Jobs.shared.fraction)
            }
        }
        present(.working(t, nil), hideAfter: nil)
    }
    func success(_ t: String, urls: [URL]) { outputs = urls; present(.success(t), hideAfter: 3) }
    func failure(_ t: String) {
        outputs = []
        NSSound.beep()
        present(.failure(t), hideAfter: 6)
    }

    private func present(_ s: State, hideAfter: TimeInterval?) {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 80),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.contentView = NSHostingView(rootView: HUDView(model: model) { [weak self] in self?.tapped() })
            panel = p
        }
        model.state = s
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let vf = screen?.visibleFrame, let p = panel {
            p.setFrameOrigin(NSPoint(x: vf.midX - p.frame.width / 2, y: vf.minY + 60))
        }
        panel?.orderFrontRegardless()
        hideWork?.cancel()
        if let t = hideAfter {
            let w = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
            hideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: w)
        }
    }

    private func tapped() {
        if !outputs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
        panel?.orderOut(nil)
    }
}

struct HUDView: View {
    @ObservedObject var model: HUD.Model
    var onTap: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            content
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.1)))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
                .onTapGesture(perform: onTap)
            Spacer(minLength: 0)
        }
        .frame(width: 620, height: 80)
    }

    @ViewBuilder var content: some View {
        switch model.state {
        case .idle:
            EmptyView()
        case .working(let t, let f):
            HStack(spacing: 10) {
                ProgressRing(fraction: f).frame(width: 18, height: 18)
                Text(t)
                if let f { Text("\(Int(f * 100))%").monospacedDigit().foregroundStyle(.secondary) }
            }
        case .success(let t):
            HStack(spacing: 8) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text(t) }
        case .failure(let t):
            HStack(spacing: 8) { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red); Text(t) }
                .frame(maxWidth: 560)
        }
    }
}

/// Determinate ring when the fraction is known, spinning arc otherwise.
struct ProgressRing: View {
    var fraction: Double?

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.15), lineWidth: 3)
            if let fraction {
                Circle().trim(from: 0, to: max(0.02, fraction))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.25), value: fraction)
            } else {
                TimelineView(.animation) { ctx in
                    Circle().trim(from: 0, to: 0.28)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(ctx.date.timeIntervalSinceReferenceDate * 400))
                }
            }
        }
    }
}

// MARK: - Float shelf

final class FloatShelf {
    static let shared = FloatShelf()
    final class Model: ObservableObject { @Published var urls: [URL] = [] }

    let model = Model()
    private var panel: NSPanel?

    func add(_ urls: [URL]) {
        for u in urls where !model.urls.contains(u) { model.urls.append(u) }
        show()
    }

    func show() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 320),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.title = "Float"
            p.level = .floating
            p.isFloatingPanel = true
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.contentView = NSHostingView(rootView: ShelfView(model: model))
            let m = NSEvent.mouseLocation
            p.setFrameTopLeftPoint(NSPoint(x: m.x + 40, y: m.y + 120))
            panel = p
        }
        panel?.orderFrontRegardless()
    }
}

struct ShelfView: View {
    @ObservedObject var model: FloatShelf.Model

    var body: some View {
        VStack(spacing: 0) {
            if model.urls.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text(L("Trascina qui i file da tenere a portata di mano")).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(model.urls, id: \.self) { u in
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable().frame(width: 28, height: 28)
                            Text(u.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { model.urls.removeAll { $0 == u } } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        }
                        .contentShape(Rectangle())
                        .onDrag { NSItemProvider(object: u as NSURL) }
                    }
                }
                Divider()
                HStack {
                    Text(L("Trascina fuori i file")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Svuota")) { model.urls.removeAll() }.controlSize(.small)
                }
                .padding(8)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { if !model.urls.contains(url) { model.urls.append(url) } } }
                }
            }
            return true
        }
    }
}
