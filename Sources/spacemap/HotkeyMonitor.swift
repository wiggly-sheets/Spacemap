import Cocoa

class HotkeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var mediaKeyMonitor: Any?
    private let onTrigger: () -> Void
    private let targetKey: HotkeyKey
    private let targetModifiers: CGEventFlags
    private var isStarted = false

    func stop() {
        guard isStarted else { return }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let monitor = mediaKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        eventTap = nil
        runLoopSource = nil
        mediaKeyMonitor = nil
        isStarted = false
    }

    init(config: HotkeyConfig, onTrigger: @escaping () -> Void) {
        self.targetKey = config.key
        self.targetModifiers = config.modifiers
        self.onTrigger = onTrigger
    }

    func start() {
        guard !isStarted else { return }
        if case .none = targetKey { return }

        if !AXIsProcessTrusted() {
            NSLog("Spacemap/Hotkey: accessibility not yet granted")
            let isRestarting = CommandLine.arguments.contains("--restarting")
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: !isRestarting] as CFDictionary
            let granted = AXIsProcessTrustedWithOptions(opts)
            if !granted {
                // Poll every 2 seconds until user grants permission
                var pollCount = 0
                let maxPolls = 15
                _ = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                    guard let self else { timer.invalidate(); return }
                    pollCount += 1
                    if AXIsProcessTrusted() {
                        timer.invalidate()
                        self.start()
                    } else if pollCount >= maxPolls {
                        timer.invalidate()
                    }
                }
                return
            }
        }

        isStarted = true
        createTap()
        createMediaKeyMonitor()
    }

    private func createTap() {
        guard case .keyCode = targetKey else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

                guard type == .keyDown else { return Unmanaged.passUnretained(event) }
                // Ignore auto-repeat events
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                    return Unmanaged.passUnretained(event)
                }
                let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags.intersection([.maskControl, .maskCommand,
                                                      .maskAlternate, .maskShift])

                if case .keyCode(let targetKeyCode) = monitor.targetKey,
                   keyCode == targetKeyCode,
                   flags == monitor.targetModifiers {
                    DispatchQueue.main.async { monitor.onTrigger() }
                    return nil
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else {
            print("Spacemap: CGEvent tap failed even though trusted — retrying")
            isStarted = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.start()
            }
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("Spacemap: hotkey active")
    }

    private func createMediaKeyMonitor() {
        guard case .mediaKey = targetKey else { return }
        mediaKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.systemDefined]) { [weak self] event in
            guard let self else { return }
            guard event.type == .systemDefined, event.subtype.rawValue == 8 else { return }
            let keyCode = Int((event.data1 & 0xFFFF0000) >> 16)
            let keyState = ((event.data1 & 0x0000FFFF) >> 8) & 0x0F
            guard keyState == 0xA || keyState == 0xB else { return }
            if self.matchesMediaKey(code: keyCode) {
                DispatchQueue.main.async { self.onTrigger() }
            }
        }
    }

    private func matchesMediaKey(code: Int) -> Bool {
        guard case .mediaKey(let target) = targetKey else { return false }
        switch (target, code) {
        case (.playPause, 16): return true
        case (.nextTrack, 17): return true
        case (.previousTrack, 18): return true
        case (.volumeUp, 0): return true
        case (.volumeDown, 1): return true
        case (.mute, 7): return true
        case (.brightnessUp, 2): return true
        case (.brightnessDown, 3): return true
        default: return false
        }
    }
}
