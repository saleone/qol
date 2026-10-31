import AppKit

/// Reports windows that open in any regular app: windows created while the app is running
/// (AXWindowCreated) and the initial windows of apps that launch.
@MainActor
final class WindowObserver {
    private let onNewWindow: (AXWindow) -> Void
    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []

    /// Apps often set their final frame (restored or cascaded) right after creating a window;
    /// acting a moment later keeps them from overriding our placement.
    private static let settleDelay: TimeInterval = 0.15
    /// A freshly launched app may not answer AX requests yet.
    private static let registrationRetries = 10
    private static let registrationRetryDelay: TimeInterval = 0.5

    init(onNewWindow: @escaping (AXWindow) -> Void) {
        self.onNewWindow = onNewWindow
    }

    func start() {
        guard workspaceTokens.isEmpty else { return }
        for app in NSWorkspace.shared.runningApplications {
            observe(app, attempt: 0)
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { self?.appLaunched(app) }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { self?.stopObserving(app.processIdentifier) }
            },
        ]
    }

    private func appLaunched(_ app: NSRunningApplication) {
        observe(app, attempt: 0)
        // Windows created before the observer was registered never send AXWindowCreated.
        let pid = app.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            MainActor.assumeIsolated {
                for window in AXUIElementCreateApplication(pid).windows {
                    self?.report(window)
                }
            }
        }
    }

    private func observe(_ app: NSRunningApplication, attempt: Int) {
        let pid = app.processIdentifier
        guard app.activationPolicy == .regular, pid != getpid(), observers[pid] == nil, !app.isTerminated else { return }

        var created: AXObserver?
        guard AXObserverCreate(pid, windowCreatedCallback, &created) == .success, let observer = created else { return }
        let status = AXObserverAddNotification(
            observer,
            AXUIElementCreateApplication(pid),
            kAXWindowCreatedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
        switch status {
        case .success, .notificationAlreadyRegistered:
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observers[pid] = observer
        case .cannotComplete where attempt < Self.registrationRetries:
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.registrationRetryDelay) { [weak self] in
                MainActor.assumeIsolated { self?.observe(app, attempt: attempt + 1) }
            }
        default:
            break
        }
    }

    private func stopObserving(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    fileprivate func windowCreated(_ element: AXUIElement) {
        let window = AXWindow(element: element)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            MainActor.assumeIsolated { self?.report(window) }
        }
    }

    private func report(_ window: AXWindow) {
        guard window.isTileable else { return }
        onNewWindow(window)
    }
}

/// AX delivers on the run loop the source was added to: the main one.
private func windowCreatedCallback(
    _: AXObserver, element: AXUIElement, _: CFString, refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let observer = Unmanaged<WindowObserver>.fromOpaque(refcon).takeUnretainedValue()
    // AXUIElement is an immutable CF reference; safe to hand to the main actor we are already on.
    nonisolated(unsafe) let element = element
    MainActor.assumeIsolated { observer.windowCreated(element) }
}
