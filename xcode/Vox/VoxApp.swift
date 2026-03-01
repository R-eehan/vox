// VoxApp.swift — Entry point for the macOS menu bar STT app
// ============================================================
//
// This wires the AppController to the SwiftUI menu bar UI.
//
// WHAT WENT WRONG IN v1:
// The `.onAppear` modifier triggered `controller.setup()`, but
// `.onAppear` only fires when the MenuBarExtra PANEL opens (user
// clicks the icon). So the model didn't start loading until the
// user clicked the menu bar icon — pressing the hotkey before
// that did nothing.
//
// THE FIX (v2):
// Initialization happens in AppController.init(), which runs
// immediately when `@StateObject` creates the controller at app
// launch. No `.onAppear` needed. The model starts loading the
// moment the app starts, not when the user first interacts.
// ============================================================

import SwiftUI

@main
struct VoxApp: App {

    // @StateObject creates the controller once and keeps it alive
    // for the lifetime of the app. AppController.init() starts
    // model loading and hotkey registration immediately.
    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 12) {

                // Status header
                HStack {
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
                Text("⌥Space to start/stop dictation")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Quit button
                Button("Quit Vox") {
                    controller.teardown()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding()
            .frame(width: 300)
            // NOTE: No .onAppear { controller.setup() } — init handles it
        } label: {
            Image(systemName: iconForState(controller.state))
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - UI Helpers

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
