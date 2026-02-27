// app/Sources/Vox/VoxApp.swift
// ============================================================
// Vox — Entry point for the macOS menu bar STT app.
//
// This wires the AppController (which orchestrates the pipeline)
// to the SwiftUI menu bar UI. The UI shows:
//   - Current state (loading, idle, listening, processing)
//   - Live transcription text
//   - Error messages
//   - Quit button
//
// The menu bar icon changes based on state:
//   🎙 mic.fill (idle) → 🔴 record.circle (listening) →
//   ⏳ ellipsis.circle (processing)
// ============================================================

import SwiftUI

// @main marks this struct as the app's entry point.
// In SwiftUI, the App protocol replaces the old AppDelegate pattern.
@main
struct VoxApp: App {

    // @StateObject creates the controller once and keeps it alive
    // for the lifetime of the app. It's the SwiftUI equivalent of
    // a singleton — but with automatic lifecycle management.
    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            // --- Menu Bar Panel Content ---
            VStack(alignment: .leading, spacing: 12) {

                // Status header
                HStack {
                    // State-dependent icon
                    Image(systemName: iconForState(controller.state))
                        .foregroundColor(colorForState(controller.state))
                    Text(controller.state.rawValue)
                        .font(.headline)
                }

                // Show current transcription text when available
                if !controller.currentText.isEmpty {
                    Text(controller.currentText)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(5)
                        .frame(maxWidth: 280, alignment: .leading)
                }

                // Show error if present
                if let error = controller.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Divider()

                // Hotkey hint
                Text("⌘⇧V to start/stop dictation")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Quit button — essential for menu bar apps since there's
                // no window close button or Dock icon to right-click.
                Button("Quit Vox") {
                    controller.teardown()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding()
            .frame(width: 300)
            .onAppear {
                // Initialize the controller when the menu bar panel
                // first appears. This triggers model download + load
                // and registers the global hotkey.
                controller.setup()
            }
        } label: {
            // --- Menu Bar Icon ---
            // This is what appears in the macOS menu bar.
            // We change the icon based on the current state.
            Image(systemName: iconForState(controller.state))
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - UI Helpers

    /// Map app state to an SF Symbols icon name
    private func iconForState(_ state: VoxState) -> String {
        switch state {
        case .loading: return "arrow.down.circle"
        case .idle: return "mic.fill"
        case .listening: return "record.circle.fill"
        case .processing: return "ellipsis.circle.fill"
        case .inserting: return "doc.on.clipboard"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    /// Map app state to a color for the icon
    private func colorForState(_ state: VoxState) -> Color {
        switch state {
        case .loading: return .orange
        case .idle: return .primary
        case .listening: return .red
        case .processing: return .orange
        case .inserting: return .blue
        case .error: return .red
        }
    }
}
