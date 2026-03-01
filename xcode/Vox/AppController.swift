// AppController.swift — The orchestrator that connects all components
// ============================================================
//
// THE FULL PIPELINE
//
// This is the central nervous system of Vox. It wires together:
//   Hotkey press → Audio capture → Model inference →
//   Text cleanup → Clipboard paste → Done
//
// State machine:
//   LOADING → (model ready) → IDLE
//   IDLE → (hotkey) → LISTENING → (hotkey) → PROCESSING →
//   (done) → INSERTING → (done) → IDLE
//   Any state → ERROR → (hotkey) → recovery attempt
//
// WHAT WENT WRONG IN v1:
//
// 1. `setup()` was called from `.onAppear` in VoxApp.swift.
//    `.onAppear` fires when the MenuBarExtra PANEL opens — i.e.,
//    when the user clicks the menu bar icon. So the model didn't
//    start loading until the user clicked the icon. If they just
//    launched the app and immediately pressed the hotkey, nothing
//    happened because the model wasn't loaded yet.
//
// 2. The `.error` state was a dead end. Once in error, there was
//    no way to recover — the user had to quit and relaunch.
//
// THE FIX (v2):
// - Move initialization to AppController.init() so it starts
//   immediately at app launch — no user interaction required.
// - Add error recovery: if the hotkey is pressed while in .error
//   state, attempt to reinitialize or reset to .idle.
// - Add state guards: only allow valid state transitions.
// ============================================================

import SwiftUI
import AVFoundation  // For AVCaptureDevice.requestAccess (microphone permission)
import Combine
import os

private let logger = Logger(subsystem: "com.reehan.vox", category: "AppController")

/// The possible states of the dictation pipeline.
/// Each state maps to a different UI treatment in the menu bar.
enum VoxState: String {
    case loading = "Loading model..."
    case idle = "Ready"
    case listening = "Listening..."
    case processing = "Processing..."
    case inserting = "Inserting..."
    case error = "Error"
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

    // MARK: - Initialization

    /// Initialize immediately at app launch.
    ///
    /// v1 BUG: Setup was triggered by `.onAppear` on the MenuBarExtra
    /// panel, which only fires when the user clicks the menu bar icon.
    /// This meant the model didn't start loading until the first click.
    ///
    /// v2 FIX: We do everything in init() so the model starts loading
    /// the moment the app launches. By the time the user presses the
    /// hotkey (even seconds after launch), the model is likely ready.
    init() {
        logger.info("AppController.init() — starting initialization")

        // Wire the hotkey to our toggle handler.
        hotkeyManager.onToggle = { [weak self] isActive in
            Task { @MainActor in
                guard let self = self else { return }
                logger.info("Hotkey toggled: isActive=\(isActive)")
                if isActive {
                    await self.startDictation()
                } else {
                    await self.stopDictation()
                }
            }
        }
        hotkeyManager.register()
        logger.info("Hotkey registered (Option+Space)")

        // Forward transcriber's currentText to our published property.
        transcriber.$currentText
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentText)

        // Start loading the model and requesting permissions immediately.
        Task {
            // Request microphone permission proactively at launch.
            // On macOS, AVAudioEngine.inputNode triggers a mic access check.
            // If the app hasn't been authorized yet, the engine starts but
            // delivers almost no audio data (the "throwing -10877" error).
            // By requesting permission here, the user sees the dialog on
            // first launch — before they ever press the hotkey.
            await requestMicrophonePermission()
            await loadModel()
        }
    }

    // MARK: - Permissions

    /// Request microphone access from the user.
    ///
    /// WHY THIS IS NEEDED:
    /// On macOS 14+, accessing AVAudioEngine.inputNode without prior
    /// microphone authorization causes CoreAudio error -10877. The engine
    /// starts but delivers almost no audio data — you get ~1600 samples
    /// (0.1s) instead of the full recording. The permission dialog only
    /// appears if you explicitly call requestAccess(for: .audio).
    ///
    /// Without this call, the NSMicrophoneUsageDescription in Info.plist
    /// is never triggered — that key only defines the *message* in the
    /// dialog, not *when* the dialog appears.
    private func requestMicrophonePermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        logger.info("Microphone permission status: \(status.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")

        switch status {
        case .authorized:
            logger.info("Microphone permission already granted")
        case .notDetermined:
            logger.info("Requesting microphone permission...")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            logger.info("Microphone permission \(granted ? "granted" : "denied") by user")
            if !granted {
                state = .error
                errorMessage = "Microphone access denied. Grant permission in System Settings > Privacy > Microphone."
            }
        case .denied, .restricted:
            logger.error("Microphone permission denied/restricted")
            state = .error
            errorMessage = "Microphone access denied. Grant permission in System Settings > Privacy > Microphone."
        @unknown default:
            break
        }
    }

    // MARK: - Model Loading

    /// Load the WhisperKit model. Called at init and on error recovery.
    private func loadModel() async {
        let oldState = state
        state = .loading
        logger.info("State: \(oldState.rawValue) → \(self.state.rawValue)")

        do {
            try await transcriber.initialize()
            state = .idle
            errorMessage = nil
            logger.info("Model ready — state set to idle")
        } catch {
            state = .error
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            logger.error("Model initialization failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pipeline Control

    /// Start the dictation pipeline.
    ///
    /// State guard: only allows transition from .idle.
    /// If in .error state, attempts recovery instead.
    private func startDictation() async {
        let oldState = state
        logger.info("startDictation called, state=\(oldState.rawValue), modelLoaded=\(self.transcriber.isModelLoaded)")

        // ERROR RECOVERY: If we're in error state and the user presses
        // the hotkey, try to recover instead of ignoring the press.
        if state == .error {
            logger.info("Attempting error recovery...")
            if transcriber.isModelLoaded {
                // Model is loaded — just reset to idle and start listening
                state = .idle
                errorMessage = nil
                logger.info("Recovered from error — model was already loaded")
                // Fall through to start listening below
            } else {
                // Model not loaded — retry initialization
                hotkeyManager.reset()
                await loadModel()
                return
            }
        }

        // STATE GUARD: Only allow transition from .idle
        guard state == .idle else {
            logger.warning("startDictation blocked — not in idle state (current: \(self.state.rawValue))")
            hotkeyManager.reset()
            return
        }

        // Check model is loaded
        guard transcriber.isModelLoaded else {
            errorMessage = "Model is still loading, please wait..."
            hotkeyManager.reset()
            logger.warning("Dictation blocked — model not loaded yet")
            return
        }

        // Defensive mic permission check before recording.
        // The proactive check at init should have already granted this,
        // but if the user revoked permission after launch, catch it here.
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard micStatus == .authorized else {
            logger.error("Microphone not authorized (status: \(micStatus.rawValue)) — requesting again")
            await requestMicrophonePermission()
            hotkeyManager.reset()
            return
        }

        do {
            state = .listening
            errorMessage = nil
            logger.info("State: \(oldState.rawValue) → \(self.state.rawValue)")
            try transcriber.startListening()
            logger.info("Dictation started — listening")
        } catch {
            state = .error
            errorMessage = "Failed to start listening: \(error.localizedDescription)"
            hotkeyManager.reset()
            logger.error("startListening failed: \(error.localizedDescription)")
        }
    }

    /// Stop dictation, process, and insert text.
    ///
    /// Full pipeline:
    ///   1. Stop recording → get audio samples
    ///   2. WhisperKit transcribes the audio
    ///   3. TextProcessor cleans up filler words
    ///   4. TextInserter pastes into the active app
    ///   5. Return to idle
    private func stopDictation() async {
        let oldState = state
        logger.info("stopDictation called, state=\(oldState.rawValue)")

        do {
            // Step 1: Stop recording and transcribe
            state = .processing
            logger.info("State: \(oldState.rawValue) → \(self.state.rawValue)")
            try await transcriber.stopListening()

            // Step 2: Get the raw transcription
            let rawText = transcriber.getFinalText()
            logger.info("Raw transcription: '\(rawText)'")

            guard !rawText.isEmpty else {
                logger.warning("Empty transcription — returning to idle")
                state = .idle
                hotkeyManager.reset()
                return
            }

            // Step 3: Clean up filler words
            let cleanedText = TextProcessor.process(rawText)
            logger.info("Cleaned text: '\(cleanedText)'")

            // Step 4: Insert into active app via clipboard paste
            state = .inserting
            logger.info("State: processing → \(self.state.rawValue)")
            let success = await TextInserter.insert(cleanedText)
            logger.info("Text insertion success: \(success)")

            if !success {
                errorMessage = "Failed to insert text. Check Accessibility permission."
            }

            // Step 5: Return to idle
            state = .idle
            currentText = cleanedText
            hotkeyManager.reset()
            logger.info("Pipeline complete — back to idle")

        } catch {
            state = .error
            errorMessage = "Dictation failed: \(error.localizedDescription)"
            hotkeyManager.reset()
            logger.error("stopDictation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Cleanup

    func teardown() {
        hotkeyManager.unregister()
        transcriber.cleanup()
    }
}
