import Foundation
import Carbon.HIToolbox

/// Global hotkeys via Carbon's RegisterEventHotKey: needs no extra permission and
/// swallows the key combo system-wide.
@MainActor
final class HotKeys {
    private static let signature: OSType = 0x4453_504C // "DSPL"
    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    /// `modifiers` uses Carbon masks (`controlKey`, `optionKey`, ...); `keyCode` a `kVK_*` code.
    func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        let id = UInt32(actions.count + 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers),
                                         EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("DisplaySplit: hotkey \(keyCode) is taken by another app (status \(status))")
            return
        }
        refs.append(ref)
        actions[id] = action
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }
}

/// Carbon dispatches application-target events on the main thread.
private func hotKeyHandler(_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard status == noErr else { return status }
    let hotKeys = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { hotKeys.fire(id.id) }
    return noErr
}
