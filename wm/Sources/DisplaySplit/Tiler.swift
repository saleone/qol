import AppKit
import DisplaySplitCore

/// Moves windows into the columns of whichever screen they are on.
@MainActor
final class Tiler {
    private let settings: Settings

    init(settings: Settings) {
        self.settings = settings
    }

    func place(_ window: AXWindow, in column: Column) {
        guard let pid = window.pid, let current = window.frame,
              let primaryHeight = NSScreen.screens.first?.frame.height,
              let screen = screen(containing: current, primaryHeight: primaryHeight)
        else { return }

        let layout = ColumnLayout(visibleFrame: screen.visibleFrame, screenSize: screen.frame.size,
                                  split: settings.load().config.split)
        let target = flipVertically(layout.frame(for: column), primaryScreenHeight: primaryHeight)

        AXUIElementCreateApplication(pid).withEnhancedUserInterfaceDisabled {
            window.setFrame(target)
            // Windows with size increments (terminals) or min/max sizes end up a little off;
            // center what we got so the slack is split evenly instead of piling up on one side.
            if let actual = window.frame, actual.size != target.size {
                window.setOrigin(centered(actual.size, in: target).origin)
            }
        }
    }

    func moveFocusedWindow(to column: Column) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let window = AXUIElementCreateApplication(app.processIdentifier).focusedWindow,
              window.isTileable
        else { return }
        place(window, in: column)
    }

    /// Moves every tileable window of every regular app into the center column.
    func centerAllWindows() {
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != getpid() {
            for window in AXUIElementCreateApplication(app.processIdentifier).windows where window.isTileable {
                place(window, in: .center)
            }
        }
    }

    /// Screen with the largest overlap with `rect` (AX coordinates); main screen if none overlaps.
    private func screen(containing rect: CGRect, primaryHeight: CGFloat) -> NSScreen? {
        let best = NSScreen.screens.max { a, b in
            overlap(rect, a, primaryHeight) < overlap(rect, b, primaryHeight)
        }
        guard let best, overlap(rect, best, primaryHeight) > 0 else { return NSScreen.main }
        return best
    }

    private func overlap(_ rect: CGRect, _ screen: NSScreen, _ primaryHeight: CGFloat) -> CGFloat {
        let screenFrame = flipVertically(screen.frame, primaryScreenHeight: primaryHeight)
        let intersection = rect.intersection(screenFrame)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
