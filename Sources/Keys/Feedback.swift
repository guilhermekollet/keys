import SwiftUI

/// A short message at the foot of the main window after an action: what was copied and when the
/// clipboard lets go of it, or what was deleted with a way to bring it back. One at a time; a
/// new one takes the place of the last.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let symbol: String
    /// How long it shows. With `countdown`, a bar empties over that time.
    let seconds: Double
    var countdown = false
    var actionTitle: String?
    var action: (() -> Void)?

    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

@MainActor
final class Toaster: ObservableObject {
    static let shared = Toaster()
    @Published private(set) var current: Toast?
    private var hiding: Task<Void, Never>?

    func show(_ toast: Toast) {
        current = toast
        hiding?.cancel()
        hiding = Task { [weak self] in
            try? await Task.sleep(for: .seconds(toast.seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss(toast.id)
        }
    }

    func dismiss(_ id: Toast.ID? = nil) {
        guard id == nil || current?.id == id else { return }
        current = nil
    }

    /// After a copy: a secret the clipboard clears later says when, with a bar running out.
    func copied(clearsAfter seconds: Int?) {
        if let seconds {
            show(Toast(text: localized("Copiado. Sai da área de transferência em \(seconds) s."), symbol: "doc.on.clipboard", seconds: Double(seconds), countdown: true))
        } else {
            show(Toast(text: localized("Copiado"), symbol: "doc.on.clipboard", seconds: 1.8))
        }
    }

    /// After deleting something that can be put back.
    func deleted(_ text: String, undo: @escaping () -> Void) {
        show(Toast(text: text, symbol: "trash", seconds: 6, countdown: true, actionTitle: localized("Desfazer"), action: undo))
    }
}

/// The toast at the foot of the window: it rises in, or fades in when motion is reduced.
struct ToastOverlay: View {
    @ObservedObject var toaster = Toaster.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let toast = toaster.current {
                ToastView(toast: toast) { toaster.dismiss(toast.id) }
                    .id(toast.id)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: toaster.current?.id)
        .padding(.bottom, 18)
    }
}

struct ToastView: View {
    let toast: Toast
    let close: () -> Void
    @State private var remaining: CGFloat = 1

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.paper.opacity(0.75))
            Text(toast.text)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
            if let title = toast.actionTitle, let action = toast.action {
                Button(title) {
                    action()
                    close()
                }
                .buttonStyle(PillButtonStyle())
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, toast.actionTitle == nil ? 16 : 8)
        .padding(.vertical, 9)
        .background(Theme.panel, in: Capsule())
        .overlay(alignment: .bottom) {
            if toast.countdown {
                // The time left, running out from right to left along the foot.
                GeometryReader { geometry in
                    Capsule()
                        .fill(Theme.paper.opacity(0.35))
                        .frame(width: geometry.size.width * remaining, height: 2)
                }
                .frame(height: 2)
                .padding(.horizontal, 16)
                .padding(.bottom, 3)
            }
        }
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: Theme.shadow, radius: 14, y: 4)
        .onAppear {
            withAnimation(.linear(duration: toast.seconds)) { remaining = 0 }
        }
        .accessibilityElement(children: .combine)
    }
}

/// How the last edits fared, by the title bar's buttons: saving, saved (for a moment), or not
/// saved, which stays until a save works.
struct SaveStatusView: View {
    @EnvironmentObject private var vault: Vault
    @State private var showsSaved = false
    @State private var hiding: Task<Void, Never>?

    var body: some View {
        Group {
            switch vault.saveStatus {
            case .saving:
                label(localized("Salvando…"), symbol: "arrow.triangle.2.circlepath", color: Theme.muted)
            case .failed:
                label(localized("Não salvo"), symbol: "exclamationmark.triangle", color: Theme.color(.amber))
                    .help(vault.problem ?? localized("O cofre não pôde ser salvo."))
            case .saved where showsSaved:
                label(localized("Salvo"), symbol: "checkmark", color: Theme.muted)
            default:
                EmptyView()
            }
        }
        .animation(.easeOut(duration: 0.2), value: vault.saveStatus)
        .animation(.easeOut(duration: 0.2), value: showsSaved)
        .onChange(of: vault.saveStatus) { _, status in
            hiding?.cancel()
            showsSaved = status == .saved
            guard status == .saved else { return }
            hiding = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                showsSaved = false
            }
        }
    }

    private func label(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
            .transition(.opacity)
            .fixedSize()
    }
}
