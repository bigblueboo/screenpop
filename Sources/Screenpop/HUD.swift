import AppKit
import Observation
import SwiftUI

/// One capture's state as shown in the floating preview.
@MainActor @Observable
final class CaptureCard {
    let image: NSImage
    let isCutout: Bool
    let copied: Bool
    var url: URL
    var isNaming = true
    var note: String?

    init(image: CGImage, url: URL, isCutout: Bool, copied: Bool) {
        self.image = NSImage(cgImage: image, size: .zero)
        self.url = url
        self.isCutout = isCutout
        self.copied = copied
    }

    /// Always says whether the image is on the clipboard, even when a note replaces the hint.
    var subtitle: String {
        let detail = note ?? "Drag it anywhere, or click to show in Finder."
        return copied ? "Copied. \(detail)" : detail
    }
}

/// A macOS-style floating thumbnail in the corner: click to reveal, drag to use.
@MainActor
final class HUD {
    private static let size = CGSize(width: 340, height: 92)
    private static let margin: CGFloat = 16

    private var panel: NSPanel?
    private var current: CaptureCard?
    private var hovering = false
    private var dismissTask: Task<Void, Never>?

    func present(_ card: CaptureCard) {
        panel?.orderOut(nil)
        dismissTask?.cancel()
        current = card
        hovering = false

        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: CardView(card: card) { [weak self] inside in
            self?.hover(inside, card: card)
        })

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let frame = CGRect(x: visible.maxX - Self.size.width - Self.margin, y: visible.minY + Self.margin,
                           width: Self.size.width, height: Self.size.height)
        panel.setFrame(frame.offsetBy(dx: 24, dy: 0), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
        self.panel = panel
    }

    /// The card has its final name; start the dismiss countdown.
    func settle(_ card: CaptureCard) {
        guard card === current, !hovering else { return }
        scheduleDismiss(after: .seconds(4))
    }

    private func hover(_ inside: Bool, card: CaptureCard) {
        guard card === current else { return }
        hovering = inside
        if inside {
            dismissTask?.cancel()
        } else if !card.isNaming {
            scheduleDismiss(after: .seconds(1.5))
        }
    }

    private func scheduleDismiss(after delay: Duration) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func dismiss() {
        guard let panel else { return }
        self.panel = nil
        current = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            panel.animator().setFrame(panel.frame.offsetBy(dx: 24, dy: 0), display: true)
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }
}

private struct CardView: View {
    let card: CaptureCard
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: card.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .background {
                    if card.isCutout { Checkerboard().opacity(0.5) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(card.isNaming ? "Naming…" : card.url.deletingPathExtension().lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .contentTransition(.opacity)
                    if card.isNaming { ProgressView().controlSize(.mini) }
                }
                Text(card.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .animation(.easeOut(duration: 0.2), value: card.isNaming)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 340, height: 92)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12))
        }
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .onTapGesture { NSWorkspace.shared.activateFileViewerSelecting([card.url]) }
        .onDrag { NSItemProvider(contentsOf: card.url) ?? NSItemProvider() }
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 6
            for row in 0..<Int(size.height / cell) + 1 {
                for col in 0..<Int(size.width / cell) + 1 where (row + col).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                                 with: .color(.gray.opacity(0.35)))
                }
            }
        }
    }
}
