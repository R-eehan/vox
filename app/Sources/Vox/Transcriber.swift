// app/Sources/Vox/Transcriber.swift
// ============================================================
// Transcriber — Wraps WhisperKit for speech-to-text.
//
// WhisperKit is a Swift-native framework that runs OpenAI's
// Whisper model on Apple Silicon via CoreML.
//
// Key architecture insight: Whisper was designed for BATCH
// transcription — you give it up to 30 seconds of audio and
// it returns the full text. It was NOT designed for streaming.
//
// WhisperKit works around this limitation by processing the
// complete audio buffer when recording stops. This means:
//   - No partial results while speaking (unlike Moonshine v2)
//   - All transcription happens after the user stops recording
//   - But excellent accuracy because it sees the full context
//
// The first time you run the app, WhisperKit will download
// the model from HuggingFace (~1-2 GB for large-v3-turbo).
// Subsequent launches use the cached model.
//
// NOTE: We originally tried Moonshine v2 (preferred for its
// native streaming and 258ms latency), but its XCFramework
// has linking issues with SPM when building without full Xcode.
// The macOS arm64 slice exists but SPM doesn't properly link
// the binary target's static library symbols. WhisperKit is
// our fallback — slightly higher latency but battle-tested
// on macOS with CoreML + Apple Neural Engine acceleration.
// ============================================================

import Foundation
import WhisperKit
import AVFoundation

// ObservableObject lets SwiftUI views automatically update
// when @Published properties change. This is how the menu bar
// UI will show real-time transcription status.
@MainActor
class VoxTranscriber: ObservableObject {

    // MARK: - Published State
    // @Published properties trigger SwiftUI view updates automatically.

    /// The current transcription text (updates after recording stops)
    @Published var currentText: String = ""

    /// Whether the transcriber is actively listening
    @Published var isListening: Bool = false

    /// Any error message to display
    @Published var errorMessage: String?

    /// Whether the WhisperKit model has been loaded and is ready
    @Published var isModelLoaded: Bool = false

    // MARK: - Private Properties

    /// The WhisperKit pipeline — handles tokenization, feature
    /// extraction, encoding, and decoding in one object.
    private var whisperKit: WhisperKit?

    /// Audio engine for capturing microphone input.
    /// AVAudioEngine is Apple's real-time audio processing framework.
    /// It provides a graph of audio nodes (input, effects, output).
    /// We tap the input node to get raw microphone data.
    private var audioEngine: AVAudioEngine?

    /// Buffer to accumulate audio samples while recording.
    /// We collect all audio, then transcribe in batch when recording stops.
    private var audioBuffer: [Float] = []

    // MARK: - Initialization

    /// Download and load the Whisper model.
    /// This is async because model download can take minutes on first run.
    ///
    /// Model selection: "large-v3-turbo" is the best balance of accuracy
    /// and speed for Apple Silicon. On M5, it runs in real-time or faster.
    /// WhisperKit auto-downloads the model from HuggingFace and caches
    /// it locally (~1-2 GB) for subsequent launches.
    func initialize() async throws {
        // WhisperKit() with a config auto-selects the best compute
        // options for your hardware and downloads the model.
        // On Apple Silicon, this leverages the Neural Engine (ANE)
        // for encoder and decoder inference.
        whisperKit = try await WhisperKit(
            WhisperKitConfig(model: "large-v3-turbo")
        )
        isModelLoaded = true
    }

    // MARK: - Control

    /// Start recording audio from the microphone.
    ///
    /// Sets up AVAudioEngine with a tap on the input node.
    /// Audio samples are accumulated in audioBuffer for later transcription.
    func startListening() throws {
        audioBuffer = []
        currentText = ""

        // Create a fresh audio engine for each recording session.
        // AVAudioEngine manages a graph of audio processing nodes.
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        let inputNode = audioEngine.inputNode
        // Get the hardware's native format (usually 48kHz stereo on Mac).
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Install a "tap" on the input node — this is a callback that
        // receives chunks of audio data as they arrive from the mic.
        // bufferSize: 1024 samples per chunk (~21ms at 48kHz).
        //
        // The closure runs on an audio thread, NOT the main thread.
        // We extract the Float data immediately, then dispatch to
        // the main actor to append to our buffer.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
            [weak self] buffer, _ in
            // Convert the audio buffer to a Float array.
            // floatChannelData gives us raw PCM samples as Float32.
            // We take channel 0 (mono) — even if stereo, channel 0 suffices.
            guard let channelData = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frames))

            // Dispatch to main actor to safely append to our buffer.
            // This is needed because audioBuffer is on a @MainActor class.
            Task { @MainActor in
                self?.audioBuffer.append(contentsOf: samples)
            }
        }

        try audioEngine.start()
        isListening = true
    }

    /// Stop recording and transcribe the accumulated audio.
    ///
    /// This is where the actual STT inference happens. WhisperKit
    /// processes the entire audio buffer at once (batch mode).
    /// On M5 with large-v3-turbo, expect ~1-3 seconds for a
    /// typical 5-10 second utterance.
    func stopListening() async throws {
        // Stop the audio engine and remove our tap.
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        isListening = false

        // Now transcribe the accumulated audio.
        guard let whisperKit = whisperKit, !audioBuffer.isEmpty else { return }

        // WhisperKit's transcribe method processes the raw audio array.
        // It handles resampling internally (48kHz → 16kHz) via its
        // audio processor pipeline. The result includes text, segments
        // with timestamps, and confidence scores.
        let results = try await whisperKit.transcribe(audioArray: audioBuffer)

        // Combine text from all result segments.
        // Usually there's one result, but long audio may produce multiple.
        currentText = results.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get the final transcribed text.
    func getFinalText() -> String {
        return currentText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Cleanup

    /// Release audio engine resources.
    func cleanup() {
        audioEngine?.stop()
        audioEngine = nil
    }
}
