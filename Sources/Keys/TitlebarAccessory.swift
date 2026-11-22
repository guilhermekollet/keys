import AppKit
import SwiftUI

/// Puts `content` in the title bar, right after the window's close, minimize and zoom buttons, for
/// as long as the view is on screen. A toolbar item can't sit that close: macOS starts them further
/// right, and one moved with an offset doesn't take clicks outside its original place.
struct LeadingTitlebarAccessory<Content: View>: NSViewRepresentable {
    @ViewBuilder let content: Content

    func makeNSView(context: Context) -> TitlebarAccessoryAnchor {
        TitlebarAccessoryAnchor(content: AnyView(content))
    }

    func updateNSView(_ view: TitlebarAccessoryAnchor, context: Context) {}

    static func dismantleNSView(_ view: TitlebarAccessoryAnchor, coordinator: ()) {
        view.detach()
    }
}

/// An empty view that finds the window to put the accessory in, and takes it out again.
final class TitlebarAccessoryAnchor: NSView {
    private let accessory = NSTitlebarAccessoryViewController()

    init(content: AnyView) {
        super.init(frame: .zero)
        let host = NSHostingView(rootView: AnyView(content.frame(maxHeight: .infinity)))
        // It is in the title bar, so the title bar's safe area would push it down.
        host.safeAreaRegions = []
        // AppKit stretches it to the bar's height; only the width is the content's.
        host.frame.size.width = host.fittingSize.width
        accessory.layoutAttribute = .leading
        accessory.view = host
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        detach()
        window?.addTitlebarAccessoryViewController(accessory)
    }

    func detach() {
        // The controller can only be taken out by its place in the list of the window it's in.
        guard let window = accessory.view.window,
              let index = window.titlebarAccessoryViewControllers.firstIndex(of: accessory) else { return }
        window.removeTitlebarAccessoryViewController(at: index)
    }
}
