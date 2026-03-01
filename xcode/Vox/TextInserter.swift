// TextInserter.swift — Inserts transcribed text at the cursor position
// ============================================================
//
// THE INVISIBLE UX LAYER
//
// This is what separates a "transcription tool" from a "dictation
// product." The user speaks, and text appears where their cursor
// is — in any app, any text field. No copy-paste, no switching.
//
// HOW IT WORKS:
//   1. Save the current clipboard contents
//   2. Write our transcribed text to the clipboard
//   3. Simulate Cmd+V (paste) via CGEvent
//   4. Wait briefly for the paste to complete
//   5. Restore the original clipboard contents
//
// WHAT WENT WRONG IN v1:
// Three bugs in our CGEvent implementation:
//
// 1. Used `nil` event source instead of `.privateState`
//    → Synthetic events could interfere with real user input
//    → VoiceInk uses `.privateState` to isolate synthetic events
//
// 2. Posted to `.cgAnnotatedSessionEventTap` instead of `.cghidEventTap`
//    → Wrong tap point. `.cghidEventTap` is the standard for synthetic
//      input — it's what VoiceInk uses. `.cgAnnotatedSessionEventTap`
//      is for event monitoring, not posting.
//
// 3. Only created keyDown + keyUp for V, didn't create separate
//    events for Command modifier down/up
//    → VoiceInk creates ALL FOUR events: cmdDown, vDown, vUp, cmdUp
//    → Sets .maskCommand on ALL four events
//
// 4. No QWERTY keyboard layout handling
//    → Virtual keycode 0x09 is positional — it's the key in the
//      V position on a QWERTY layout. On Dvorak, that physical key
//      types a different character. VoiceInk temporarily switches
//      to QWERTY before posting events, then restores.
//
// 5. No AppleScript fallback
//    → Some apps (certain Electron apps, custom text engines) block
//      synthetic CGEvents. VoiceInk falls back to:
//        tell application "System Events"
//            keystroke "v" using command down
//        end tell
//
// THE FIX (v2):
// We copied VoiceInk's battle-tested CursorPaster.swift approach:
// - `.privateState` event source
// - `.cghidEventTap` posting
// - 4-event pattern with .maskCommand on all
// - QWERTY detection and temporary switch
// - AppleScript fallback
//
// REQUIRES: Accessibility permission in System Settings >
//   Privacy & Security > Accessibility. Without this, CGEvent
//   posting is silently blocked by macOS. The TCC permission is
//   tied to the app's CFBundleIdentifier — this is why we moved
//   to an Xcode project with a stable bundle ID (com.reehan.vox).
//   With SPM builds, the code signing identity changed every rebuild.
// ============================================================

import AppKit
import Carbon
import os

private let logger = Logger(subsystem: "com.reehan.vox", category: "TextInserter")

struct TextInserter {

    /// Insert text at the current cursor position in the active app.
    ///
    /// Uses the clipboard-paste approach that VoiceInk, Wispr Flow,
    /// and every production dictation app uses. Saves clipboard,
    /// writes our text, simulates Cmd+V, restores clipboard.
    ///
    /// - Parameter text: The transcribed text to insert
    /// - Returns: true if insertion was attempted
    @MainActor
    static func insert(_ text: String) async -> Bool {
        guard !text.isEmpty else { return false }

        // Check Accessibility permission and log result for debugging.
        // AXIsProcessTrusted() returns true if our bundle ID is in the
        // TCC database (System Settings > Privacy > Accessibility).
        //
        // IMPORTANT: In v1, this always failed even when toggled ON
        // because SPM builds don't produce a stable CFBundleIdentifier.
        // The auto-generated signing identity changed every rebuild,
        // so macOS thought it was a different app each time.
        // With the Xcode project, our bundle ID is always com.reehan.vox.
        let isTrusted = AXIsProcessTrusted()
        logger.info("AXIsProcessTrusted: \(isTrusted)")

        guard isTrusted else {
            logger.warning("Accessibility permission not granted — opening System Settings")
            promptForAccessibility()
            return false
        }

        // --- Step 1: Save current clipboard ---
        let pasteboard = NSPasteboard.general
        let savedContents = savePasteboard(pasteboard)

        // --- Step 2: Write our text to clipboard ---
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // --- Step 3: Wait 50ms for clipboard to settle ---
        // VoiceInk does this. Without it, some apps read the clipboard
        // before our write has fully propagated through the pasteboard
        // server (pbs daemon).
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // --- Step 4: Simulate Cmd+V via CGEvent ---
        let pasteSuccess = simulatePaste()

        if !pasteSuccess {
            // --- Step 4b: AppleScript fallback ---
            // Some apps block synthetic CGEvents. Fall back to asking
            // System Events to perform the keystroke via Apple Events.
            logger.info("CGEvent paste failed — trying AppleScript fallback")
            appleScriptPaste()
        }

        // --- Step 5: Wait for paste to complete ---
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // --- Step 6: Restore original clipboard ---
        restorePasteboard(pasteboard, contents: savedContents)

        return true
    }

    // MARK: - Clipboard Save/Restore

    /// Save all clipboard items and their types.
    private static func savePasteboard(_ pasteboard: NSPasteboard) -> [(NSPasteboard.PasteboardType, Data)] {
        var saved: [(NSPasteboard.PasteboardType, Data)] = []
        for item in pasteboard.pasteboardItems ?? [] {
            for type in item.types {
                if let data = item.data(forType: type) {
                    saved.append((type, data))
                }
            }
        }
        return saved
    }

    /// Restore previously saved clipboard contents.
    private static func restorePasteboard(_ pasteboard: NSPasteboard, contents: [(NSPasteboard.PasteboardType, Data)]) {
        pasteboard.clearContents()
        if contents.isEmpty { return }

        let item = NSPasteboardItem()
        for (type, data) in contents {
            item.setData(data, forType: type)
        }
        pasteboard.writeObjects([item])
    }

    // MARK: - Keyboard Simulation (VoiceInk Pattern)

    /// Simulate Cmd+V using VoiceInk's proven 4-event pattern.
    ///
    /// Creates four separate CGEvents:
    ///   1. Command key down
    ///   2. V key down (with Command modifier)
    ///   3. V key up (with Command modifier)
    ///   4. Command key up
    ///
    /// All four events use `.maskCommand` flag and are posted to
    /// `.cghidEventTap` (HID = Human Interface Device — the lowest
    /// level, as if events came from the physical keyboard).
    ///
    /// Uses `CGEventSource(stateID: .privateState)` to isolate our
    /// synthetic events from real user input. Without this, our
    /// events could be affected by keys the user is physically
    /// holding down (e.g., if they're still holding Option from
    /// the hotkey press).
    ///
    /// Returns false if event creation fails (usually means no
    /// Accessibility permission).
    @discardableResult
    private static func simulatePaste() -> Bool {
        // Ensure we're using a QWERTY keyboard layout.
        // Virtual keycode 0x09 is POSITIONAL — it's the physical key
        // where V sits on a QWERTY layout. On Dvorak, that key types
        // something else. We temporarily switch to QWERTY if needed.
        let previousInputSource = switchToQWERTYIfNeeded()

        // Create a private event source — isolates our synthetic events
        // from the real keyboard state. VoiceInk does the same.
        let eventSource = CGEventSource(stateID: .privateState)

        // Virtual keycode for V on QWERTY layout
        let vKeyCode: CGKeyCode = 0x09
        // Virtual keycode for Command (left) — 0x37
        let cmdKeyCode: CGKeyCode = 0x37

        // Create all four events
        guard let cmdDown = CGEvent(keyboardEventSource: eventSource, virtualKey: cmdKeyCode, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: eventSource, virtualKey: vKeyCode, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: eventSource, virtualKey: vKeyCode, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: eventSource, virtualKey: cmdKeyCode, keyDown: false) else {
            logger.error("Failed to create CGEvents — Accessibility permission likely missing")
            restoreInputSource(previousInputSource)
            return false
        }

        // Set Command modifier on ALL four events.
        // VoiceInk sets this on every event, not just the V events.
        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        cmdUp.flags = .maskCommand

        // Post to .cghidEventTap — this is the standard tap point for
        // synthetic keyboard input. VoiceInk uses this, not
        // .cgAnnotatedSessionEventTap (which is for event monitoring).
        cmdDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        cmdUp.post(tap: .cghidEventTap)

        // Restore the original keyboard layout after a short delay.
        // 100ms gives the paste events time to be processed before
        // we switch the keyboard layout back.
        if let previousInputSource = previousInputSource {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                restoreInputSource(previousInputSource)
            }
        }

        logger.info("CGEvent Cmd+V posted to .cghidEventTap")
        return true
    }

    // MARK: - QWERTY Keyboard Layout Handling

    /// Check if the current keyboard input source is QWERTY.
    /// If not, temporarily switch to QWERTY and return the previous
    /// input source so we can restore it after pasting.
    ///
    /// WHY: Virtual keycode 0x09 maps to the physical key in the
    /// "V" position on a QWERTY layout. On Dvorak, AZERTY, etc.,
    /// that physical key produces a different character. Since CGEvent
    /// uses physical keycodes (not characters), we need QWERTY active
    /// for Cmd+V to actually paste.
    ///
    /// VoiceInk does the same thing in CursorPaster.swift.
    private static func switchToQWERTYIfNeeded() -> TISInputSource? {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }

        // Get the input source ID (e.g., "com.apple.keylayout.US" for QWERTY)
        guard let sourceIDPtr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) else {
            return nil
        }
        let sourceID = Unmanaged<CFString>.fromOpaque(sourceIDPtr).takeUnretainedValue() as String

        // Check if it's already a QWERTY-compatible layout
        let qwertyLayouts = [
            "com.apple.keylayout.US",
            "com.apple.keylayout.USInternational-PC",
            "com.apple.keylayout.British",
            "com.apple.keylayout.Australian",
            "com.apple.keylayout.Canadian",
            "com.apple.keylayout.ABC",
            "com.apple.keylayout.USExtended",
        ]

        if qwertyLayouts.contains(sourceID) {
            return nil // Already QWERTY, no switch needed
        }

        logger.info("Non-QWERTY layout detected (\(sourceID)) — switching to US QWERTY for paste")

        // Find and activate US QWERTY
        let filter = [
            kTISPropertyInputSourceID: "com.apple.keylayout.US"
        ] as CFDictionary

        guard let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              let qwertySource = sources.first else {
            logger.warning("Could not find US QWERTY layout — paste may use wrong key")
            return nil
        }

        TISSelectInputSource(qwertySource)
        return currentSource
    }

    /// Restore the keyboard input source that was active before we
    /// switched to QWERTY for pasting.
    private static func restoreInputSource(_ source: TISInputSource?) {
        guard let source = source else { return }
        TISSelectInputSource(source)
        logger.info("Restored original keyboard layout")
    }

    // MARK: - AppleScript Fallback

    /// Fallback paste method using AppleScript.
    ///
    /// Some apps (certain Electron apps, custom text engines) block
    /// synthetic CGEvents from untrusted sources. AppleScript goes
    /// through a different path — it asks System Events to perform
    /// the keystroke, which some apps handle better.
    ///
    /// This requires the `com.apple.security.automation.apple-events`
    /// entitlement, which we set in Vox.entitlements.
    private static func appleScriptPaste() {
        let script = NSAppleScript(source: """
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """)

        var error: NSDictionary?
        script?.executeAndReturnError(&error)

        if let error = error {
            logger.error("AppleScript paste failed: \(error)")
        } else {
            logger.info("AppleScript paste succeeded")
        }
    }

    // MARK: - Accessibility Permission

    /// Open System Settings to the Accessibility permission page.
    private static func promptForAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
