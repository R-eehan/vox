// app/Sources/Vox/TextInserter.swift
// ============================================================
// TextInserter — Inserts text into the currently focused app.
//
// THE INVISIBLE UX LAYER
//
// This is what separates a "transcription tool" from a
// "dictation product." The user speaks, and text appears
// where their cursor is — in any app, any text field.
//
// How every production STT app does this (including Wispr Flow):
//   1. Save the current clipboard contents
//   2. Write our transcribed text to the clipboard
//   3. Simulate Cmd+V (paste) via CGEvent
//   4. Restore the original clipboard contents
//
// Why clipboard paste and not direct text insertion?
//   - AXUIElement (Accessibility API) can insert text directly,
//     but many apps don't implement it properly (Electron apps,
//     web browsers with contentEditable, custom text engines)
//   - Keyboard simulation (CGEvent keystrokes) is character-by-
//     character and visibly slow for long text
//   - Clipboard paste works in 99%+ of apps and is instant
//
// The tradeoff: We temporarily overwrite the user's clipboard.
// We save and restore it, but this is fragile — the clipboard
// can contain images, files, rich text, and other complex types
// that are hard to perfectly preserve.
//
// REQUIRES: Accessibility permission in System Settings >
//   Privacy & Security > Accessibility. Without this, CGEvent
//   posting to other apps is silently blocked by macOS.
// ============================================================

import AppKit  // For NSPasteboard (clipboard access)

struct TextInserter {

    /// Insert text into the currently focused text field of the active app.
    ///
    /// This function:
    ///   1. Saves the clipboard
    ///   2. Writes our text to the clipboard
    ///   3. Simulates Cmd+V
    ///   4. Waits briefly for the paste to complete
    ///   5. Restores the original clipboard
    ///
    /// - Parameter text: The transcribed text to insert
    /// - Returns: true if insertion was attempted (no guarantee of success)
    @MainActor
    static func insert(_ text: String) async -> Bool {
        // Guard: Don't try to insert empty text
        guard !text.isEmpty else { return false }

        // Guard: Check if we have Accessibility permission
        // AXIsProcessTrusted() returns true if the user has granted
        // Accessibility access to this app in System Settings.
        // Without it, our CGEvent posts will be silently ignored.
        guard AXIsProcessTrusted() else {
            // Open System Settings to the right page so the user
            // can grant permission
            promptForAccessibility()
            return false
        }

        // --- Step 1: Save current clipboard ---
        // NSPasteboard.general is the system clipboard (same one
        // used by Cmd+C / Cmd+V). We save its current contents
        // so we can restore them after our paste.
        let pasteboard = NSPasteboard.general
        let savedContents = savePasteboard(pasteboard)

        // --- Step 2: Write our text to clipboard ---
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // --- Step 3: Simulate Cmd+V (paste) ---
        // CGEvent is a Core Graphics API for creating and posting
        // synthetic input events. We create keyboard events for:
        //   - Key down: V key with Command modifier
        //   - Key up: V key with Command modifier
        //
        // The kVK_ANSI_V constant (0x09) is the virtual keycode
        // for the V key on ANSI keyboards.
        simulatePaste()

        // --- Step 4: Wait for paste to complete ---
        // The paste operation is asynchronous — macOS needs time
        // to deliver the event to the target app and for that app
        // to process it. 100ms is typically enough.
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // --- Step 5: Restore original clipboard ---
        restorePasteboard(pasteboard, contents: savedContents)

        return true
    }

    // MARK: - Clipboard Save/Restore

    /// Save all clipboard items and their types.
    /// The clipboard can contain multiple items in multiple formats
    /// (e.g., both plain text and rich text for the same copy).
    private static func savePasteboard(_ pasteboard: NSPasteboard) -> [(NSPasteboard.PasteboardType, Data)] {
        var saved: [(NSPasteboard.PasteboardType, Data)] = []
        // pasteboardItems contains all items on the clipboard
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

    // MARK: - Keyboard Simulation

    /// Simulate Cmd+V keystroke to paste from clipboard.
    private static func simulatePaste() {
        // Virtual keycode for 'V' on ANSI keyboard layout
        let vKeyCode: CGKeyCode = 0x09

        // Create key-down event with Command modifier
        // CGEvent(keyboardEventSource:virtualKey:keyDown:)
        //   - source: nil = system event source
        //   - virtualKey: the key to press
        //   - keyDown: true = press, false = release
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false)

        // Add the Command modifier flag (⌘)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        // Post events to the HID (Human Interface Device) event tap.
        // This is the lowest level — events appear as if they came
        // from the physical keyboard.
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }

    // MARK: - Accessibility Permission

    /// Open System Settings to the Accessibility page.
    /// The user needs to add Vox to the list of allowed apps.
    private static func promptForAccessibility() {
        // This URL scheme opens System Settings directly to
        // Privacy & Security > Accessibility
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
