import ApplicationServices

/// Thin wrapper over an Accessibility window element. Frames are in AX coordinates
/// (top-left origin of the primary display).
struct AXWindow {
    let element: AXUIElement

    var pid: pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }

    /// Standard, resizable, on-screen window: the kind worth tiling. Excludes dialogs,
    /// sheets, panels, popovers, minimized and full-screen windows.
    var isTileable: Bool {
        string(kAXRoleAttribute) == kAXWindowRole
            && string(kAXSubroleAttribute) == kAXStandardWindowSubrole
            && bool(kAXMinimizedAttribute) != true
            && bool("AXFullScreen") != true
            && bool(kAXModalAttribute) != true
            && isSettable(kAXSizeAttribute)
            && isSettable(kAXPositionAttribute)
    }

    var frame: CGRect? {
        guard let origin: CGPoint = axValue(kAXPositionAttribute, .cgPoint),
              let size: CGSize = axValue(kAXSizeAttribute, .cgSize)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Size, then position, then size again: the first resize lets the window fit at the new
    /// position, the second applies the size the window server may have clamped when the
    /// window was still near a screen edge or on another display.
    func setFrame(_ rect: CGRect) {
        setSize(rect.size)
        setOrigin(rect.origin)
        setSize(rect.size)
    }

    func setOrigin(_ origin: CGPoint) {
        var origin = origin
        if let value = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        }
    }

    private func setSize(_ size: CGSize) {
        var size = size
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        }
    }

    private func copy(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private func string(_ attribute: String) -> String? { copy(attribute) as? String }

    private func bool(_ attribute: String) -> Bool? { copy(attribute) as? Bool }

    private func isSettable(_ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
            && settable.boolValue
    }

    private func axValue<T>(_ attribute: String, _ type: AXValueType) -> T? {
        guard let raw = copy(attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = raw as! AXValue
        let result = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { result.deallocate() }
        guard AXValueGetValue(value, type, result) else { return nil }
        return result.pointee
    }
}

extension AXUIElement {
    /// Windows of an application element, in front-to-back order.
    var windows: [AXWindow] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement]
        else { return [] }
        return elements.map(AXWindow.init)
    }

    var focusedWindow: AXWindow? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return AXWindow(element: value as! AXUIElement)
    }

    /// Runs `body` with the app's AXEnhancedUserInterface turned off. When VoiceOver-style
    /// enhanced UI is on, apps animate AX-driven moves and often end at the wrong frame.
    func withEnhancedUserInterfaceDisabled(_ body: () -> Void) {
        let attribute = "AXEnhancedUserInterface" as CFString
        var value: CFTypeRef?
        let wasEnabled = AXUIElementCopyAttributeValue(self, attribute, &value) == .success
            && (value as? Bool) == true
        if wasEnabled { AXUIElementSetAttributeValue(self, attribute, kCFBooleanFalse) }
        body()
        if wasEnabled { AXUIElementSetAttributeValue(self, attribute, kCFBooleanTrue) }
    }
}
