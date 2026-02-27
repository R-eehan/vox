// app/Sources/Vox/AppController.swift
// ============================================================
// AppController — The orchestrator that connects all components.
//
// THE FULL PIPELINE
//
// This is the central nervous system of Vox. It wires together:
//   Hotkey press → Audio capture → Model inference →
//   Text cleanup → Clipboard paste → Done
//
// In product terms, this is the "integration layer" — the code
// that makes individual capabilities feel like a cohesive product.
// Each component (transcriber, processor, inserter) works
// independently, but the controller makes them work TOGETHER.
//
// State machine:
//   IDLE → (hotkey pressed) → LISTENING → (hotkey pressed) →
//   PROCESSING → (done) → INSERTING → (done) → IDLE
// ============================================================

import SwiftUI
import Combine

/// The possible states of the dictation pipeline.
/// Each state maps to a different UI treatment in the menu bar.
enum VoxState: String {
    case loading = "Loading model..."     // Model is being downloaded/loaded
    case idle = "Ready"                    // Waiting for hotkey
    case listening = "Listening..."        // Recording audio
    case processing = "Processing..."      // Model is transcribing
    case inserting = "Inserting..."         // Pasting into active app
    case error = "Error"                   // Something went wrong
}

@MainActor
class AppController: ObservableObject {

    // MARK: - Published State (drives the SwiftUI UI)

    @Published var state: VoxState = .loading
    @Published var currentText: String = ""
    @Published var errorMessage: String?

    // MARK: - Components

    let transcriber = VoxTranscriber()
    let hotkeyManager = HotkeyManager()

    // MARK: - Subscriptions
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Setup

    /// Initialize the controller: load the model, register hotkey.
    ///
    /// This is called when the menu bar panel first appears.
    /// Model loading is async because WhisperKit downloads the model
    /// from HuggingFace on first run (~1-2 GB for large-v3-turbo).
    func setup() {
        // Wire the hotkey to our toggle handler.
        // When the user presses Cmd+Shift+V, this closure fires.
        // It determines whether to start or stop dictation based
        // on the toggle state.
        hotkeyManager.onToggle = { [weak self] isActive in
            Task { @MainActor in
                if isActive {
                    await self?.startDictation()
                } else {
                    await self?.stopDictation()
                }
            }
        }
        hotkeyManager.register()

        // Forward transcriber's currentText to our published property.
        // This lets the UI show live transcription updates.
        transcriber.$currentText
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentText)

        // Load the WhisperKit model in the background.
        // This downloads the model on first run and loads it into memory.
        // The user sees "Loading model..." until this completes.
        Task {
            do {
                try await transcriber.initialize()
                state = .idle
            } catch {
                state = .error
                errorMessage = "Failed to load model: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Pipeline Control

    /// Start the dictation pipeline.
    /// Called when user presses the hotkey the first time.
    private func startDictation() async {
        // Don't start if model isn't loaded yet
        guard transcriber.isModelLoaded else {
            errorMessage = "Model is still loading, please wait..."
            hotkeyManager.reset()
            return
        }

        do {
            state = .listening
            errorMessage = nil
            try transcriber.startListening()
        } catch {
            state = .error
            errorMessage = "Failed to start listening: \(error.localizedDescription)"
            hotkeyManager.reset()
        }
    }

    /// Stop dictation, process, and insert text.
    /// Called when user presses the hotkey the second time.
    ///
    /// This is where the full pipeline runs:
    ///   1. Stop recording → WhisperKit transcribes the audio
    ///   2. TextProcessor cleans up filler words
    ///   3. TextInserter pastes into the active app
    private func stopDictation() async {
        do {
            // Step 1: Stop recording and transcribe.
            // For WhisperKit, this is where the actual model inference
            // happens — it processes the entire audio buffer at once.
            state = .processing
            try await transcriber.stopListening()

            // Step 2: Get the raw transcription
            let rawText = transcriber.getFinalText()
            guard !rawText.isEmpty else {
                state = .idle
                hotkeyManager.reset()
                return
            }

            // Step 3: Clean up filler words.
            // This is our "product engineering" layer — simple regex
            // vs. Wispr Flow's cloud LLM. See TextProcessor.swift
            // for the detailed comparison.
            let cleanedText = TextProcessor.process(rawText)

            // Step 4: Insert into active app via clipboard paste.
            state = .inserting
            let success = await TextInserter.insert(cleanedText)

            if !success {
                errorMessage = "Failed to insert text. Check Accessibility permission."
            }

            // Step 5: Return to idle.
            state = .idle
            currentText = cleanedText
            hotkeyManager.reset()

        } catch {
            state = .error
            errorMessage = "Dictation failed: \(error.localizedDescription)"
            hotkeyManager.reset()
        }
    }

    // MARK: - Cleanup

    func teardown() {
        hotkeyManager.unregister()
        transcriber.cleanup()
    }
}
