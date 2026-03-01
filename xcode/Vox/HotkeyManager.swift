// HotkeyManager.swift — Global hotkey for push-to-talk
// ============================================================
//
// THE ACTIVATION UX
//
// A dictation tool is useless if activating it is clunky.
// The user needs to be able to start speaking instantly from
// any app, without switching windows or clicking anything.
//
// We use the HotKey library (by Sam Soffes) which wraps the
// Carbon RegisterEventHotKey API. Carbon is Apple's legacy C
// framework — deprecated since macOS 10.8 but still the ONLY
// way to register a global hotkey that "swallows" the keystroke
// (so Option+Space doesn't also type a space in the active app).
//
// Default hotkey: Option+Space (⌥␣)
// Why: Easy one-hand reach, doesn't conflict with common shortcuts.
//
// Toggle pattern:
//   1. Press Option+Space → start listening (mic activates)
//   2. Speak your text
//   3. Press Option+Space → stop listening, process, insert
// ============================================================

import Foundation
import HotKey
import Carbon

@MainActor
class HotkeyManager: ObservableObject {

    // MARK: - Properties

    private var hotKey: HotKey?

    /// Callback: true = start recording, false = stop recording
    var onToggle: ((Bool) -> Void)?

    /// Toggle state: first press = start, second = stop
    @Published var isActive: Bool = false

    // MARK: - Setup

    func register() {
        hotKey = HotKey(key: .space, modifiers: [.option])

        hotKey?.keyDownHandler = { [weak self] in
            guard let self = self else { return }
            self.isActive.toggle()
            self.onToggle?(self.isActive)
        }
    }

    func unregister() {
        hotKey = nil
    }

    /// Reset to inactive state (e.g., after pipeline completes)
    func reset() {
        isActive = false
    }
}
