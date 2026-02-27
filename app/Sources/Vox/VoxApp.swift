// app/Sources/Vox/VoxApp.swift
// ============================================================
// Vox — Entry point for the macOS menu bar STT app.
//
// This file sets up a "menu bar extra" — an app that lives
// entirely in the macOS menu bar (the row of icons in the
// top-right of the screen, next to the clock).
//
// Key SwiftUI concept: MenuBarExtra is a Scene type that
// creates a menu bar icon. When clicked, it shows either a
// simple menu (.menu style) or a custom SwiftUI view
// (.window style). We use .window for richer UI later.
//
// LSUIElement = true (set in Info.plist) tells macOS to hide
// this app from the Dock and App Switcher — it's menu-bar-only.
// ============================================================

import SwiftUI

// @main marks this struct as the app's entry point.
// In SwiftUI, the App protocol replaces the old AppDelegate pattern.
@main
struct VoxApp: App {

    // The body property defines the app's scene hierarchy.
    // A "scene" in SwiftUI is a top-level container (window, menu bar item, etc.)
    var body: some Scene {
        // MenuBarExtra creates a persistent icon in the macOS menu bar.
        // Parameters:
        //   - "Vox": accessibility label for the menu bar item
        //   - systemImage: SF Symbols icon name (mic.fill = microphone)
        MenuBarExtra("Vox", systemImage: "mic.fill") {
            // This closure defines what appears when the user clicks the icon.
            VStack(spacing: 12) {
                Text("Vox")
                    .font(.headline)
                Text("Speech-to-Text")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                // Quit button — essential for menu bar apps since there's
                // no window close button or Dock icon to right-click.
                Button("Quit Vox") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding()
        }
        // .window style renders the menu bar content as a floating panel
        // (like a popover), allowing any SwiftUI view — not just menu items.
        .menuBarExtraStyle(.window)
    }
}
