import Cocoa

class HotkeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onTrigger: () -> Void
    private let targetKeyCode: CGKeyCode
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
        eventTap = nil
        runLoopSource = nil
        isStarted = false
    }

    init(config: HotkeyConfig, onTrigger: @escaping () -> Void) {
        self.targetKeyCode = config.keyCode
        self.targetModifiers = config.modifiers
        self.onTrigger = onTrigger
    }

    func start() {
        guard !isStarted else { return }

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
    }

    private func createTap() {
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

                if keyCode == monitor.targetKeyCode && flags == monitor.targetModifiers {
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
}
