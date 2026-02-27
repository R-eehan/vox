// app/Sources/Vox/HotkeyManager.swift
// ============================================================
// HotkeyManager — Global hotkey to start/stop dictation.
//
// THE ACTIVATION UX
//
// A dictation tool is useless if activating it is clunky.
// The user needs to be able to start speaking instantly from
// any app, without switching windows or clicking anything.
//
// This is why global hotkeys exist: a keyboard shortcut that
// works system-wide, even when Vox is in the background.
//
// We use the HotKey library (by Sam Soffes) which wraps the
// Carbon RegisterEventHotKey API. Carbon is Apple's legacy C
// framework from the Classic Mac OS era — deprecated since
// macOS 10.8 but still the ONLY way to register a hotkey that
// "swallows" the keystroke (so it doesn't also get typed into
// the active app).
//
// Default hotkey: Cmd+Shift+V
// Why: Similar to Cmd+V (paste), easy to remember, unlikely
// to conflict with other apps.
//
// Usage pattern:
//   1. Press Cmd+Shift+V → start listening (mic activates)
//   2. Speak your text
//   3. Press Cmd+Shift+V again → stop listening, process, insert
// ============================================================

import Foundation
import HotKey
import Carbon

@MainActor
class HotkeyManager: ObservableObject {

    // MARK: - Properties

    /// The registered global hotkey.
    /// HotKey handles registration/deregistration with the OS.
    private var hotKey: HotKey?

    /// Callback fired when the user presses the hotkey.
    /// The Bool parameter indicates whether recording should
    /// start (true) or stop (false).
    var onToggle: ((Bool) -> Void)?

    /// Whether we're currently in "listening" mode.
    /// Tracks toggle state: first press = start, second = stop.
    @Published var isActive: Bool = false

    // MARK: - Setup

    /// Register the global hotkey with the system.
    ///
    /// After calling this, pressing Cmd+Shift+V anywhere in macOS
    /// will trigger our callback — even in other apps.
    func register() {
        // HotKey takes a Key enum value and modifier flags.
        // .v = the V key, .command + .shift = ⌘⇧
        hotKey = HotKey(key: .v, modifiers: [.command, .shift])

        // keyDownHandler is called when the hotkey is pressed.
        // We toggle between start and stop states.
        hotKey?.keyDownHandler = { [weak self] in
            guard let self = self else { return }
            self.isActive.toggle()
            self.onToggle?(self.isActive)
        }
    }

    /// Unregister the hotkey (cleanup).
    func unregister() {
        hotKey = nil
    }

    /// Reset to inactive state (e.g., after text insertion completes)
    func reset() {
        isActive = false
    }
}
