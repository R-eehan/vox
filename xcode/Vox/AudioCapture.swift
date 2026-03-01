// AudioCapture.swift — Microphone capture with 16kHz resampling
// ============================================================
//
// Resampling approach taken from VoiceInk (github.com/Beingpax/VoiceInk),
// an open-source macOS transcription app that ships this in production.
//
// VoiceInk's CoreAudioRecorder.swift uses manual linear interpolation
// to resample from hardware rate (48kHz) to 16kHz inside the audio
// callback. This is lightweight enough for real-time — no AVAudioConverter,
// no format objects, just simple math per sample.
//
// VoiceInk uses raw Core Audio AUHAL; we use AVAudioEngine for simplicity
// but apply the same resampling algorithm.
//
// WHY THIS FILE IS SEPARATE FROM TRANSCRIBER:
// Swift 6 strict concurrency enforces actor isolation at RUNTIME.
// AVAudioEngine's installTap closure runs on a real-time audio thread.
// If created inside a @MainActor method, Swift 6 tags it as
// @MainActor-isolated → runtime crash (EXC_BREAKPOINT / SIGTRAP).
// This class is intentionally NOT @MainActor.
// ============================================================

@preconcurrency import AVFoundation
import os

private let logger = Logger(subsystem: "com.reehan.vox", category: "AudioCapture")

/// Thread-safe audio sample accumulator.
final class AudioSampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    func append(_ pointer: UnsafeBufferPointer<Float>) {
        lock.lock()
        samples.append(contentsOf: pointer)
        lock.unlock()
    }

    func drain() -> [Float] {
        lock.lock()
        let result = samples
        samples = []
        lock.unlock()
        return result
    }

    func reset() {
        lock.lock()
        samples = []
        lock.unlock()
    }
}

/// Microphone capture with automatic resampling to 16kHz mono Float32.
///
/// Resampling uses VoiceInk's linear interpolation algorithm directly
/// in the tap callback. Buffers are pre-allocated at setup time to
/// avoid heap allocation on the audio thread.
///
/// Audio pipeline (all in the tap callback):
///   Mic (48kHz, N ch) → linear interpolation → mono 16kHz Float32 → buffer
final class AudioCapture: @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private let sampleBuffer = AudioSampleBuffer()
    private let lock = NSLock()

    /// Pre-allocated buffer for resampled output (allocated in start, freed in stop).
    /// Follows VoiceInk's pattern of pre-allocating to avoid malloc on the audio thread.
    private var conversionBuffer: UnsafeMutablePointer<Float>?
    private var conversionBufferCapacity: Int = 0

    private static let targetSampleRate: Double = 16000.0

    func start() throws {
        lock.lock()
        defer { lock.unlock() }

        sampleBuffer.reset()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Use outputFormat directly — this is what the tap actually delivers.
        let tapFormat = inputNode.outputFormat(forBus: 0)
        let sourceSampleRate = tapFormat.sampleRate
        let channelCount = Int(tapFormat.channelCount)
        let ratio = Self.targetSampleRate / sourceSampleRate  // e.g. 16000/48000 = 0.333

        logger.info("Hardware audio: \(sourceSampleRate)Hz, \(channelCount) ch")

        let needsResampling = sourceSampleRate != Self.targetSampleRate
        if needsResampling {
            logger.info("Resampling enabled: \(sourceSampleRate)Hz → \(Self.targetSampleRate)Hz (linear interpolation)")
        }

        // Pre-allocate conversion buffer (VoiceInk pattern).
        // Max 8192 input frames → at most ceil(8192 * ratio) + 1 output frames.
        let maxInputFrames = 8192
        let maxOutputFrames = Int(ceil(Double(maxInputFrames) * ratio)) + 1
        let convBuf = UnsafeMutablePointer<Float>.allocate(capacity: maxOutputFrames)
        self.conversionBuffer = convBuf
        self.conversionBufferCapacity = maxOutputFrames

        let buffer = self.sampleBuffer

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { pcmBuffer, _ in
            guard let channelData = pcmBuffer.floatChannelData else { return }
            let frameCount = Int(pcmBuffer.frameLength)

            if !needsResampling && channelCount == 1 {
                // Fast path: hardware already 16kHz mono (rare)
                buffer.append(UnsafeBufferPointer(start: channelData[0], count: frameCount))
                return
            }

            // --- VoiceInk's linear interpolation resampling ---
            // From VoiceInk/CoreAudioRecorder.swift convertAndWriteToFile()
            //
            // For each output sample at index i:
            //   1. Map i back to a fractional input index: inputIndex = i / ratio
            //   2. Find the two nearest input samples (idx1, idx2)
            //   3. Linearly interpolate between them
            //   4. Average across channels for mono mixdown
            let outputFrameCount = Int(Double(frameCount) * ratio)
            guard outputFrameCount > 0 else { return }

            for i in 0..<outputFrameCount {
                let inputIndex = Double(i) / ratio
                let idx1 = min(Int(inputIndex), frameCount - 1)
                let idx2 = min(idx1 + 1, frameCount - 1)
                let frac = Float(inputIndex - Double(idx1))

                var sample: Float = 0
                for ch in 0..<channelCount {
                    let s1 = channelData[ch][idx1]
                    let s2 = channelData[ch][idx2]
                    sample += s1 + frac * (s2 - s1)
                }
                convBuf[i] = sample / Float(channelCount)
            }

            buffer.append(UnsafeBufferPointer(start: convBuf, count: outputFrameCount))
        }

        try engine.start()
        self.audioEngine = engine
        logger.info("Audio capture started (resampling: \(needsResampling))")
    }

    /// Stop capturing and return 16kHz mono Float32 samples ready for WhisperKit.
    func stop() -> [Float] {
        lock.lock()
        defer { lock.unlock() }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        // Free pre-allocated buffer
        conversionBuffer?.deallocate()
        conversionBuffer = nil
        conversionBufferCapacity = 0

        let samples = sampleBuffer.drain()
        let duration = Double(samples.count) / Self.targetSampleRate
        logger.info("Audio capture stopped: \(samples.count) samples (\(String(format: "%.1f", duration))s at 16kHz)")
        return samples
    }

    func cleanup() {
        lock.lock()
        defer { lock.unlock() }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        conversionBuffer?.deallocate()
        conversionBuffer = nil
        conversionBufferCapacity = 0
    }
}
