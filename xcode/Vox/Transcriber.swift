// Transcriber.swift — WhisperKit speech-to-text wrapper
// ============================================================
//
// WhisperKit is a Swift-native framework that runs OpenAI's
// Whisper model on Apple Silicon via CoreML + Apple Neural Engine.
//
// KEY ARCHITECTURE INSIGHT:
// Whisper was designed for BATCH transcription — you give it up
// to 30 seconds of audio and it returns the full text. It was
// NOT designed for streaming/real-time. This is why we record
// first, then transcribe — there's no "live captions" mode.
//
// WHISPERKIT vs WHISPER.CPP TRADEOFFS:
// - WhisperKit: Pure Swift, uses CoreML → runs on ANE (Neural
//   Engine) which is power-efficient. Auto-downloads models from
//   HuggingFace. Easy SPM/Xcode integration. Downside: CoreML
//   model compilation can be slow on first load.
// - whisper.cpp: C++ with Swift bindings, uses CPU/GPU directly.
//   Faster initial load, more control, but requires manual model
//   management and bridging headers. Used by VoiceInk.
//
// We chose WhisperKit because:
// 1. Pure Swift = no bridging complexity
// 2. ANE = better battery life on laptops
// 3. Auto model download = simpler first-run experience
// 4. This is a learning project — WhisperKit's API is cleaner
//
// WHAT CHANGED IN v2:
// - Removed `@MainActor` from this class. WhisperKit's transcribe()
//   is async and does heavy computation — it shouldn't block the
//   main thread. The @Published properties are still updated from
//   the main actor via AppController's Combine pipeline.
// - Added audio validation logging: we now log the sample count
//   and estimated duration to verify resampling is working.
//   At 16kHz, 5 seconds of audio = ~80,000 samples.
//   At 48kHz (broken), 5 seconds = ~240,000 samples.
// ============================================================

import Foundation
import WhisperKit
import os

private let logger = Logger(subsystem: "com.reehan.vox", category: "Transcriber")

/// WhisperKit transcription wrapper.
///
/// Note: This class uses @MainActor because its @Published properties
/// drive SwiftUI views. The actual transcription work (whisperKit.transcribe)
/// is async and runs off the main thread automatically.
@MainActor
class VoxTranscriber: ObservableObject {

    // MARK: - Published State

    @Published var currentText: String = ""
    @Published var isListening: Bool = false
    @Published var errorMessage: String?
    @Published var isModelLoaded: Bool = false

    // MARK: - Private Properties

    private var whisperKit: WhisperKit?

    /// Audio capture runs entirely outside @MainActor.
    /// See AudioCapture.swift for why this is necessary.
    private let audioCapture = AudioCapture()

    // MARK: - Initialization

    /// Download (first run) or load (subsequent runs) the Whisper model.
    ///
    /// First run: Downloads ~1-2 GB from HuggingFace. Takes 30-120s
    /// depending on connection speed.
    /// Subsequent runs: Loads from disk cache. Takes ~10-30s for
    /// CoreML model compilation + loading into ANE.
    func initialize() async throws {
        let modelsDir = ModelManager.modelsDirectory
        try ModelManager.ensureDirectoryExists()

        // Check for cached model
        let cachedModelPath = modelsDir
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
            .appendingPathComponent("openai_whisper-large-v3_turbo")

        let modelExists = FileManager.default.fileExists(atPath: cachedModelPath.path)
        logger.info("Model cache check: exists=\(modelExists) path=\(cachedModelPath.path)")

        if modelExists {
            logger.info("Loading cached model from disk...")
            whisperKit = try await WhisperKit(
                WhisperKitConfig(modelFolder: cachedModelPath.path)
            )
        } else {
            logger.info("Downloading model from HuggingFace (first run)...")
            whisperKit = try await WhisperKit(
                WhisperKitConfig(
                    model: "large-v3_turbo",
                    downloadBase: modelsDir
                )
            )
        }

        isModelLoaded = true
        logger.info("Model loaded successfully")
    }

    // MARK: - Recording Control

    func startListening() throws {
        logger.info("startListening called")
        currentText = ""
        try audioCapture.start()
        isListening = true
    }

    func stopListening() async throws {
        logger.info("stopListening called")

        // Stop capture and get resampled 16kHz samples
        let audioSamples = audioCapture.stop()
        isListening = false

        // Audio validation logging — this is how we verify resampling works.
        // At 16kHz: 5 seconds = ~80,000 samples (CORRECT)
        // At 48kHz: 5 seconds = ~240,000 samples (BROKEN — no resampling)
        let durationEstimate = Double(audioSamples.count) / 16000.0
        logger.info("Audio: \(audioSamples.count) samples (~\(String(format: "%.1f", durationEstimate))s at 16kHz)")

        guard let whisperKit = whisperKit, !audioSamples.isEmpty else {
            logger.warning("No audio or WhisperKit not initialized")
            return
        }

        // Transcribe the audio batch. WhisperKit handles chunking
        // internally if the audio is longer than 30 seconds.
        let results = try await whisperKit.transcribe(audioArray: audioSamples)

        currentText = results.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("Transcription: '\(self.currentText)'")
    }

    func getFinalText() -> String {
        return currentText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Cleanup

    func cleanup() {
        audioCapture.cleanup()
    }
}
