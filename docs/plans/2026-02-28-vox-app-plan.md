# Vox App Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a native macOS menu bar STT app that captures speech, transcribes it locally using Moonshine v2 (or WhisperKit fallback), cleans up filler words, and inserts the text into the active app via clipboard paste.

**Architecture:** SwiftUI menu bar app using MenuBarExtra. Audio capture via AVAudioEngine (or Moonshine's built-in MicTranscriber). Model inference via Moonshine v2 Medium (native streaming, 245M params, 258ms latency). Text insertion via clipboard paste simulation (save clipboard → write text → simulate Cmd+V → restore clipboard). Global hotkey via HotKey library.

**Tech Stack:** Swift 6.1, SwiftUI, AVAudioEngine, Moonshine v2 (ONNX Runtime) / WhisperKit (CoreML), HotKey, CGEvent (Quartz)

**Design doc:** `docs/plans/2026-02-28-vox-design.md` (contains full research, rationale, sources)

**Important context for the implementer:**
- Every Swift file must have detailed comments explaining what the code does and why. This is a learning project — a PM is reading this code to understand how STT products work.
- The user runs macOS on an M5 MacBook Pro (Apple Silicon).
- This is NOT a sandboxed app. It requires Accessibility permission for text insertion.
- The app lives in the menu bar only (no Dock icon).

---

### Task 1: Verify Prerequisites

**Step 1: Check that Xcode command line tools and Swift are available**

Run:
```bash
xcode-select -p && swift --version && xcodebuild -version
```
Expected: Paths and version numbers for all three. If missing, run `xcode-select --install`.

**Step 2: Check macOS version**

Run:
```bash
sw_vers
```
Expected: macOS 15+ (Sequoia or later). MenuBarExtra requires macOS 13+.

**Step 3: Commit checkpoint**

No commit needed — just verification.

---

### Task 2: Create Swift Package Project

**Files:**
- Create: `app/Package.swift`
- Create: `app/Sources/Vox/VoxApp.swift`

**Step 1: Create the Package.swift with all dependencies**

```swift
// app/Package.swift
// ============================================================
// Package manifest for Vox — a local-first macOS STT app.
//
// Dependencies:
// - HotKey: Global hotkey registration (wraps Carbon RegisterEventHotKey)
//
// We start with HotKey only. The STT model dependency
// (Moonshine or WhisperKit) is added in Task 3 after
// the integration spike determines which one works.
// ============================================================

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vox",
    platforms: [
        // MenuBarExtra requires macOS 13 (Ventura) or later.
        // SwiftUI .window menuBarExtraStyle requires macOS 13+.
        .macOS(.v14)
    ],
    dependencies: [
        // HotKey: lightweight global hotkey library for macOS.
        // Wraps the legacy Carbon RegisterEventHotKey API, which is
        // deprecated but still the only way to "swallow" a system-wide
        // hotkey so other apps don't also see the keystroke.
        // Source: https://github.com/soffes/HotKey
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "Vox",
            dependencies: ["HotKey"],
            path: "Sources/Vox"
        ),
    ]
)
```

**Step 2: Create the minimal app entry point**

```swift
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
```

**Step 3: Create Info.plist for permissions and menu-bar-only behavior**

```bash
# Create the Info.plist in the Sources directory
# This will be embedded in the app bundle at build time.
```

Create file `app/Sources/Vox/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- LSUIElement: When true, the app has no Dock icon and doesn't
         appear in the App Switcher (Cmd+Tab). This is standard for
         menu-bar-only apps like Wispr Flow, Bartender, etc. -->
    <key>LSUIElement</key>
    <true/>

    <!-- NSMicrophoneUsageDescription: Required by macOS to show the
         microphone permission dialog. Without this key, the app will
         crash when trying to access the microphone. The string is
         shown to the user in the permission prompt. -->
    <key>NSMicrophoneUsageDescription</key>
    <string>Vox needs microphone access to transcribe your speech into text.</string>
</dict>
</plist>
```

**Step 4: Verify the project builds and runs**

Run:
```bash
cd /Users/reehan/Desktop/vox/app && swift build 2>&1
```
Expected: Build succeeds. May show warnings about concurrency, that's OK.

Run:
```bash
cd /Users/reehan/Desktop/vox/app && swift run Vox &
```
Expected: A microphone icon (🎙) appears in the macOS menu bar. Clicking it shows the "Vox" panel with a Quit button.

Kill the app after verifying:
```bash
pkill -f Vox || true
```

**Step 5: Commit**

```bash
cd /Users/reehan/Desktop/vox
git add app/
git commit -m "feat: create SwiftUI menu bar app shell with HotKey dependency

Sets up the Vox app as a Swift Package with MenuBarExtra,
Info.plist for microphone permission and LSUIElement,
and HotKey dependency for global hotkey support.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Model Integration Spike — Moonshine v2 vs WhisperKit

**Context:** Moonshine v2 is our preferred model (faster, more accurate, native streaming). But its XCFramework may only include iOS slices. This task determines which model we'll use for the rest of the build.

**Files:**
- Modify: `app/Package.swift`
- Create: `app/Sources/Vox/Transcriber.swift`

**Step 1: Try adding Moonshine v2 as a dependency**

Update `app/Package.swift` to add Moonshine:

```swift
dependencies: [
    .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
    // Moonshine v2: Open-source STT model optimized for streaming on edge devices.
    // 245M params, 6.65% WER, 258ms latency on Apple Silicon, MIT license.
    // Uses ONNX Runtime for inference (bundled in the XCFramework).
    .package(url: "https://github.com/moonshine-ai/moonshine-swift.git", from: "0.0.1"),
],
targets: [
    .executableTarget(
        name: "Vox",
        dependencies: [
            "HotKey",
            .product(name: "MoonshineVoice", package: "moonshine-swift"),
        ],
        path: "Sources/Vox"
    ),
]
```

Run:
```bash
cd /Users/reehan/Desktop/vox/app && swift build 2>&1
```

**Step 2: Evaluate the result**

**If Moonshine builds successfully for macOS:** Proceed with Moonshine. Continue to Step 3a.

**If Moonshine fails** (likely error: "no matching platform" or "unsupported architecture"): Fall back to WhisperKit. Continue to Step 3b.

**Step 3a: Moonshine works — create Transcriber with MicTranscriber**

Moonshine provides `MicTranscriber` which handles ALL audio capture + transcription:

```swift
// app/Sources/Vox/Transcriber.swift
// ============================================================
// Transcriber — Wraps Moonshine v2 for speech-to-text.
//
// Moonshine v2 is an open-source STT model by Moonshine AI
// (formerly Useful Sensors, founded by Pete Warden).
//
// Key architecture insight: Unlike Whisper (which processes
// fixed 30-second audio windows), Moonshine v2 uses an
// "ergodic streaming encoder" — it processes audio incrementally
// as it arrives. This means:
//   - No wasted compute on silence padding
//   - Sub-300ms latency (vs 1-11 seconds for Whisper)
//   - Native streaming (partial results while you speak)
//
// The MicTranscriber convenience class handles:
//   1. AVAudioEngine setup (microphone access)
//   2. Audio format conversion (any sample rate → 16kHz)
//   3. Voice Activity Detection (built-in Silero VAD)
//   4. Streaming transcription with incremental results
//
// We just need to:
//   - Initialize it with a model path
//   - Register a listener for transcription events
//   - Call start() and stop()
// ============================================================

import Foundation
import MoonshineVoice

// ObservableObject lets SwiftUI views automatically update
// when @Published properties change. This is how the menu bar
// UI will show real-time transcription status.
@MainActor
class VoxTranscriber: ObservableObject {

    // MARK: - Published State
    // @Published properties trigger SwiftUI view updates automatically.

    /// The current transcription text (updates in real-time as you speak)
    @Published var currentText: String = ""

    /// Whether the transcriber is actively listening
    @Published var isListening: Bool = false

    /// Any error message to display
    @Published var errorMessage: String?

    // MARK: - Private Properties

    /// Moonshine's all-in-one mic + transcription handler.
    /// This single class replaces what would otherwise be:
    ///   - An AVAudioEngine setup (~50 lines)
    ///   - Audio format conversion (~20 lines)
    ///   - VAD integration (~30 lines)
    ///   - Model inference pipeline (~40 lines)
    private var micTranscriber: MicTranscriber?

    /// Accumulated text from completed lines (sentences/phrases
    /// that the model has finalized and won't revise further)
    private var completedText: String = ""

    // MARK: - Initialization

    /// Set up the Moonshine model.
    /// modelPath: directory containing the .ort model files
    func initialize(modelPath: String) throws {
        // Create the MicTranscriber with our preferred settings.
        //
        // modelArch: .mediumStreaming = 245M params, best accuracy
        //   Options: .tinyStreaming (33M), .smallStreaming (123M),
        //            .mediumStreaming (245M)
        //   Tradeoff: bigger = more accurate but slower
        //
        // updateInterval: How often (in seconds) to emit transcription
        //   updates. 0.3s = responsive feel without excessive callbacks.
        //
        // sampleRate/channels/bufferSize: Audio capture settings.
        //   Moonshine resamples internally to 16kHz regardless.
        micTranscriber = try MicTranscriber(
            modelPath: modelPath,
            modelArch: .mediumStreaming,
            updateInterval: 0.3,
            sampleRate: 16000,
            channels: 1,
            bufferSize: 1024
        )

        // Register our event listener.
        // Moonshine emits events as transcription progresses:
        //   - LineStarted: new utterance detected (VAD triggered)
        //   - LineTextChanged: partial text updated (streaming result)
        //   - LineCompleted: utterance finalized (speaker paused)
        micTranscriber?.addListener { [weak self] event in
            Task { @MainActor in
                self?.handleTranscriptionEvent(event)
            }
        }
    }

    // MARK: - Control

    /// Start listening for speech
    func startListening() throws {
        completedText = ""
        currentText = ""
        try micTranscriber?.start()
        isListening = true
    }

    /// Stop listening and finalize transcription
    func stopListening() throws {
        try micTranscriber?.stop()
        isListening = false
    }

    /// Get the final transcribed text (all completed lines)
    func getFinalText() -> String {
        return completedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Event Handling

    /// Process transcription events from Moonshine.
    ///
    /// The event flow for a typical utterance:
    ///   1. LineStarted → VAD detected speech
    ///   2. LineTextChanged (repeated) → partial results stream in
    ///   3. LineCompleted → speaker paused, text is final
    private func handleTranscriptionEvent(_ event: Any) {
        if let textChanged = event as? LineTextChanged {
            // Partial result — the model's current best guess.
            // This text may change as more audio arrives.
            // We show it to give real-time feedback.
            currentText = completedText + textChanged.line.text
        } else if let completed = event as? LineCompleted {
            // Final result — the model has committed to this text.
            // It won't revise it further. Append to our completed buffer.
            completedText += completed.line.text + " "
            currentText = completedText
        } else if event is LineStarted {
            // New utterance detected — VAD triggered.
            // No action needed, just awareness.
        } else if let error = event as? TranscriptError {
            errorMessage = "Transcription error: \(error.error)"
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        micTranscriber?.close()
    }
}
```

**Step 3b: WhisperKit fallback — update Package.swift and create Transcriber**

If Moonshine doesn't build for macOS, update `app/Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
    // WhisperKit: Swift-native Whisper implementation optimized for Apple Silicon.
    // Uses CoreML for inference on the Apple Neural Engine (ANE).
    // Auto-downloads models from HuggingFace on first launch.
    // Source: https://github.com/argmaxinc/WhisperKit
    .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
],
targets: [
    .executableTarget(
        name: "Vox",
        dependencies: [
            "HotKey",
            "WhisperKit",
        ],
        path: "Sources/Vox"
    ),
]
```

Create `app/Sources/Vox/Transcriber.swift` (WhisperKit version):

```swift
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
// WhisperKit's AudioStreamTranscriber works around this by
// re-processing a sliding window of audio on each update.
// This is less efficient than Moonshine's native streaming
// but still achieves usable real-time performance on Apple
// Silicon thanks to CoreML + ANE acceleration.
//
// The first time you run the app, WhisperKit will download
// the model from HuggingFace (~1-2 GB for large-v3-turbo).
// Subsequent launches use the cached model.
// ============================================================

import Foundation
import WhisperKit
import AVFoundation

@MainActor
class VoxTranscriber: ObservableObject {

    // MARK: - Published State

    @Published var currentText: String = ""
    @Published var isListening: Bool = false
    @Published var errorMessage: String?
    @Published var isModelLoaded: Bool = false

    // MARK: - Private Properties

    /// The WhisperKit pipeline — handles tokenization, feature
    /// extraction, encoding, and decoding in one object.
    private var whisperKit: WhisperKit?

    /// Audio engine for capturing microphone input
    private var audioEngine: AVAudioEngine?

    /// Buffer to accumulate audio samples while recording
    private var audioBuffer: [Float] = []

    // MARK: - Initialization

    /// Download and load the Whisper model.
    /// This is async because model download can take minutes on first run.
    func initialize() async throws {
        // WhisperKit() with no arguments auto-selects the best model
        // for your hardware and downloads it from HuggingFace.
        // On M5, this will likely select large-v3-turbo.
        whisperKit = try await WhisperKit(
            WhisperKitConfig(model: "large-v3-turbo")
        )
        isModelLoaded = true
    }

    // MARK: - Control

    func startListening() throws {
        audioBuffer = []
        currentText = ""

        // Set up AVAudioEngine for microphone capture.
        // AVAudioEngine is Apple's real-time audio processing framework.
        // It provides a graph of audio nodes (input, effects, output).
        // We tap the input node to get raw microphone data.
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        let inputNode = audioEngine.inputNode
        // Get the hardware's native format (usually 48kHz stereo)
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Install a "tap" on the input node — this is a callback that
        // receives chunks of audio data as they arrive from the mic.
        // bufferSize: 1024 samples per chunk (~21ms at 48kHz)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
            [weak self] buffer, _ in
            // Convert the audio buffer to Float array and accumulate.
            // Whisper needs 16kHz mono Float32, but we'll convert later.
            guard let channelData = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frames))
            Task { @MainActor in
                self?.audioBuffer.append(contentsOf: samples)
            }
        }

        try audioEngine.start()
        isListening = true
    }

    func stopListening() async throws {
        // Stop the audio engine and remove our tap
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        isListening = false

        // Now transcribe the accumulated audio
        guard let whisperKit = whisperKit, !audioBuffer.isEmpty else { return }

        // Resample from hardware rate (48kHz) to Whisper's expected 16kHz.
        // WhisperKit handles this internally via its audioProcessor.
        let results = try await whisperKit.transcribe(audioArray: audioBuffer)
        currentText = results?.text ?? ""
    }

    func getFinalText() -> String {
        return currentText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Cleanup

    func cleanup() {
        audioEngine?.stop()
        audioEngine = nil
    }
}
```

**Step 4: Verify model integration builds**

Run:
```bash
cd /Users/reehan/Desktop/vox/app && swift build 2>&1
```
Expected: Build succeeds with whichever model was chosen.

**Step 5: Commit**

```bash
cd /Users/reehan/Desktop/vox
git add app/
git commit -m "feat: add STT model integration (Moonshine v2 or WhisperKit)

Integrates speech-to-text model with commented code explaining
the architecture: audio capture, VAD, streaming inference.
See docs/plans/2026-02-28-vox-design.md for model comparison.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 4: Text Processor — Filler Word Removal

**Context:** This is the "product engineering" layer that the blog teardown focuses on. Raw model output includes "um", "uh", "you know", false starts. Wispr Flow uses a cloud LLM to clean this up. We use simple regex — and the gap becomes a blog talking point.

**Files:**
- Create: `app/Sources/Vox/TextProcessor.swift`

**Step 1: Create the text processor**

```swift
// app/Sources/Vox/TextProcessor.swift
// ============================================================
// TextProcessor — Cleans up raw transcription output.
//
// THIS IS WHERE "PRODUCT ENGINEERING" BEGINS.
//
// The STT model gives you raw text: "Um so I was like you know
// thinking about uh the project and um yeah."
//
// Wispr Flow runs this through a fine-tuned Llama model on AWS
// that costs them <200ms of cloud inference per utterance. Their
// LLM doesn't just remove filler words — it rewrites the text
// to match your personal writing style, adds proper punctuation,
// and formats based on which app you're typing in.
//
// We use simple regex-based cleanup. It's fast (0ms), free,
// and runs locally. But the output quality is noticeably worse
// than Wispr Flow's. The gap between this approach and theirs
// is the "last 5%" that makes dictation software feel magical.
//
// This is a deliberate design choice, not laziness — we want
// to demonstrate the gap for the blog post.
// ============================================================

import Foundation

struct TextProcessor {

    // MARK: - Filler Words
    // These are the most common English filler words and phrases.
    // Wispr Flow handles these with an LLM that understands context.
    // We use a simple find-and-remove approach — less accurate but
    // good enough for a demo. The LLM approach would also handle:
    //   - "I mean" (sometimes filler, sometimes meaningful)
    //   - "so" at start of sentence (filler vs. conjunction)
    //   - "like" (filler vs. comparison vs. preference)
    //
    // Our regex approach will incorrectly remove some meaningful
    // uses. That's OK — it demonstrates why LLM post-processing
    // is valuable.

    /// Common filler words/phrases to remove.
    /// Each pattern uses word boundaries (\b) to avoid matching
    /// substrings (e.g., don't match "umbrella" when removing "um").
    private static let fillerPatterns: [(pattern: String, replacement: String)] = [
        // Single-word fillers
        (#"\b[Uu]mm?\b"#, ""),           // "um", "umm", "Um"
        (#"\b[Uu]hh?\b"#, ""),           // "uh", "uhh"
        (#"\b[Ee]rr?\b"#, ""),           // "er", "err"
        (#"\b[Aa]hh?\b"#, ""),           // "ah", "ahh"
        (#"\b[Hh]mm+\b"#, ""),           // "hmm", "hmmm"

        // Multi-word fillers (must come before single-word to avoid partial matches)
        (#"\byou know\b"#, ""),           // "you know"
        (#"\bI mean\b"#, ""),             // "I mean" (risky — sometimes meaningful)
        (#"\bkind of\b"#, ""),            // "kind of"
        (#"\bsort of\b"#, ""),            // "sort of"
        (#"\bbasically\b"#, ""),          // "basically"
        (#"\bactually\b"#, ""),           // "actually" (often filler in speech)
        (#"\bliterally\b"#, ""),          // "literally"

        // "like" as filler (very tricky — we only remove it when
        // preceded by a comma or at the start of a clause)
        (#",\s*like\s*,"#, ","),          // ", like," → ","
        (#"^[Ll]ike\s+"#, ""),            // "Like I was saying" → "I was saying"
    ]

    // MARK: - Processing

    /// Clean up raw transcription text.
    ///
    /// Pipeline:
    ///   1. Remove filler words/phrases
    ///   2. Clean up extra whitespace
    ///   3. Fix capitalization after removals
    ///   4. Clean up punctuation
    ///
    /// Input:  "Um so I was like you know thinking about uh the project"
    /// Output: "So I was thinking about the project"
    static func process(_ text: String) -> String {
        var result = text

        // Step 1: Remove filler words
        for (pattern, replacement) in fillerPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: replacement
                )
            }
        }

        // Step 2: Collapse multiple spaces into single space
        // After removing fillers, we get "I was  thinking" → "I was thinking"
        result = result.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )

        // Step 3: Clean up orphaned punctuation
        // Removing fillers can leave ", , the" → ", the"
        result = result.replacingOccurrences(
            of: #",\s*,"#,
            with: ",",
            options: .regularExpression
        )

        // Step 4: Trim leading/trailing whitespace
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Step 5: Capitalize first letter if needed
        if let firstChar = result.first, firstChar.isLowercase {
            result = firstChar.uppercased() + result.dropFirst()
        }

        return result
    }
}
```

**Step 2: Verify it builds**

Run:
```bash
cd /Users/reehan/Desktop/vox/app && swift build 2>&1
```
Expected: Build succeeds.

**Step 3: Commit**

```bash
cd /Users/reehan/Desktop/vox
git add app/Sources/Vox/TextProcessor.swift
git commit -m "feat: add filler word removal with commented product analysis

Regex-based text cleanup for 'um', 'uh', 'you know', etc.
Comments explain the gap between this approach and Wispr Flow's
LLM-based post-processing — the 'last 5%' product engineering.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 5: Text Insertion — Clipboard Paste Simulation

**Context:** This is the critical system integration that makes Vox a "product" instead of just a transcription tool. Text appears where the user's cursor is, in any app.

**Files:**
- Create: `app/Sources/Vox/TextInserter.swift`

**Step 1: Create the text inserter**

```swift
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
import Carbon  // For CGEvent (simulating keystrokes)

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
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
```

**Step 2: Verify it builds**

Run:
```bash
cd /Users/reehan/Desktop/vox/app && swift build 2>&1
```
Expected: Build succeeds.

**Step 3: Commit**

```bash
cd /Users/reehan/Desktop/vox
git add app/Sources/Vox/TextInserter.swift
git commit -m "feat: add clipboard paste text insertion with detailed comments

Implements the industry-standard approach: save clipboard,
write text, simulate Cmd+V, restore clipboard. Comments
explain why every STT app uses this approach and the tradeoffs.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 6: Global Hotkey — Press to Talk

**Files:**
- Create: `app/Sources/Vox/HotkeyManager.swift`

**Step 1: Create the hotkey manager**

```swift
// app/Sources/Vox/HotkeyManager.swift
// ============================================================
// HotkeyManager — Global hotkey to start/stop dictation.
//
// THE ACTIVATION UX
//
// A dictation tool is useless if activating it is clunky.
// The user needs to be able to start speaking instantly from
// any app, without switching windows or clicking anything.
//
// This is why global hotkeys exist: a keyboard shortcut that
// works system-wide, even when Vox is in the background.
//
// We use the HotKey library (by Sam Soffes) which wraps the
// Carbon RegisterEventHotKey API. Carbon is Apple's legacy C
// framework from the Classic Mac OS era — deprecated since
// macOS 10.8 but still the ONLY way to register a hotkey that
// "swallows" the keystroke (so it doesn't also get typed into
// the active app).
//
// Default hotkey: Cmd+Shift+V
// Why: Similar to Cmd+V (paste), easy to remember, unlikely
// to conflict with other apps.
//
// Usage pattern:
//   1. Press Cmd+Shift+V → start listening (mic activates)
//   2. Speak your text
//   3. Press Cmd+Shift+V again → stop listening, process, insert
// ============================================================

import Foundation
import HotKey
import Carbon

@MainActor
class HotkeyManager: ObservableObject {

    // MARK: - Properties

    /// The registered global hotkey.
    /// HotKey handles registration/deregistration with the OS.
    private var hotKey: HotKey?

    /// Callback fired when the user presses the hotkey.
    /// The Bool parameter indicates whether recording should
    /// start (true) or stop (false).
    var onToggle: ((Bool) -> Void)?

    /// Whether we're currently in "listening" mode.
    /// Tracks toggle state: first press = start, second = stop.
    @Published var isActive: Bool = false

    // MARK: - Setup

    /// Register the global hotkey with the system.
    ///
    /// After calling this, pressing Cmd+Shift+V anywhere in macOS
    /// will trigger our callback — even in other apps.
    func register() {
        // HotKey takes a Key enum value and modifier flags.
        // .v = the V key, .command + .shift = ⌘⇧
        hotKey = HotKey(key: .v, modifiers: [.command, .shift])

        // keyDownHandler is called when the hotkey is pressed.
        // We toggle between start and stop states.
        hotKey?.keyDownHandler = { [weak self] in
            guard let self = self else { return }
            self.isActive.toggle()
            self.onToggle?(self.isActive)
        }
    }

    /// Unregister the hotkey (cleanup).
    func unregister() {
        hotKey = nil
    }

    /// Reset to inactive state (e.g., after text insertion completes)
    func reset() {
        isActive = false
    }
}
```

**Step 2: Verify it builds**

Run:
```bash
cd /Users/reehan/Desktop/vox/app && swift build 2>&1
```
Expected: Build succeeds.

**Step 3: Commit**

```bash
cd /Users/reehan/Desktop/vox
git add app/Sources/Vox/HotkeyManager.swift
git commit -m "feat: add global hotkey (Cmd+Shift+V) for push-to-talk

Wraps HotKey library for system-wide hotkey registration.
Comments explain Carbon API legacy and why global hotkeys
are essential for dictation UX.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 7: Wire Everything Together — App Controller

**Context:** This task connects all the components: hotkey triggers recording, transcriber processes audio, text processor cleans output, inserter pastes into active app.

**Files:**
- Create: `app/Sources/Vox/AppController.swift`
- Modify: `app/Sources/Vox/VoxApp.swift`

**Step 1: Create the app controller that orchestrates the pipeline**

```swift
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
    case idle = "Ready"                    // Waiting for hotkey
    case listening = "Listening..."        // Recording audio
    case processing = "Processing..."      // Model is transcribing
    case inserting = "Inserting..."         // Pasting into active app
    case error = "Error"                   // Something went wrong
}

@MainActor
class AppController: ObservableObject {

    // MARK: - Published State (drives the SwiftUI UI)

    @Published var state: VoxState = .idle
    @Published var currentText: String = ""
    @Published var errorMessage: String?

    // MARK: - Components

    let transcriber = VoxTranscriber()
    let hotkeyManager = HotkeyManager()

    // MARK: - Subscriptions
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Setup

    func setup() {
        // Wire the hotkey to our toggle handler
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

        // Forward transcriber's currentText to our published property
        transcriber.$currentText
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentText)
    }

    // MARK: - Pipeline Control

    /// Start the dictation pipeline.
    /// Called when user presses the hotkey the first time.
    private func startDictation() async {
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
    private func stopDictation() async {
        do {
            // Step 1: Stop recording
            state = .processing
            try transcriber.stopListening()

            // Step 2: Get the raw transcription
            let rawText = transcriber.getFinalText()
            guard !rawText.isEmpty else {
                state = .idle
                hotkeyManager.reset()
                return
            }

            // Step 3: Clean up filler words
            // This is our "product engineering" layer — simple regex
            // vs. Wispr Flow's cloud LLM. See TextProcessor.swift
            // for the detailed comparison.
            let cleanedText = TextProcessor.process(rawText)

            // Step 4: Insert into active app via clipboard paste
            state = .inserting
            let success = await TextInserter.insert(cleanedText)

            if !success {
                errorMessage = "Failed to insert text. Check Accessibility permission."
            }

            // Step 5: Return to idle
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
```

**Step 2: Update VoxApp.swift to use the controller**

Replace the contents of `app/Sources/Vox/VoxApp.swift`:

```swift
// app/Sources/Vox/VoxApp.swift
// ============================================================
// Vox — Entry point for the macOS menu bar STT app.
//
// This wires the AppController (which orchestrates the pipeline)
// to the SwiftUI menu bar UI. The UI shows:
//   - Current state (idle, listening, processing)
//   - Live transcription text
//   - Error messages
//   - Quit button
//
// The menu bar icon changes based on state:
//   🎙 mic.fill (idle) → 🔴 record.circle (listening) →
//   ⏳ ellipsis.circle (processing)
// ============================================================

import SwiftUI

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

                // Quit button
                Button("Quit Vox") {
                    controller.teardown()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding()
            .frame(width: 300)
        } label: {
            // --- Menu Bar Icon ---
            // This is what appears in the macOS menu bar.
            // We change the icon based on the current state.
            Image(systemName: iconForState(controller.state))
        }
        .menuBarExtraStyle(.window)
        .onChange(of: controller.state) { _, _ in
            // This ensures the menu bar icon updates when state changes
        }
    }

    // MARK: - UI Helpers

    /// Map app state to an SF Symbols icon name
    private func iconForState(_ state: VoxState) -> String {
        switch state {
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
        case .idle: return .primary
        case .listening: return .red
        case .processing: return .orange
        case .inserting: return .blue
        case .error: return .red
        }
    }

    // MARK: - Lifecycle

    init() {
        // Setup is deferred to avoid issues with @StateObject initialization
        DispatchQueue.main.async {
            // Initialize model and register hotkey
            // This needs to happen after the app is fully launched
        }
    }
}
```

**Step 3: Add app lifecycle setup**

We need to handle model initialization on app launch. Add an AppDelegate or use `.onAppear`:

The cleanest approach for a menu bar app is to call `controller.setup()` when the view first appears. Update VoxApp.swift to add this in the MenuBarExtra content:

Add after the VStack's `.padding()`:
```swift
.onAppear {
    controller.setup()
    // Initialize the model in the background
    Task {
        // Model initialization happens here.
        // For Moonshine: pass the model path
        // For WhisperKit: auto-downloads from HuggingFace
        // The specific initialization code depends on which
        // model was chosen in Task 3.
    }
}
```

**Step 4: Verify it builds**

Run:
```bash
cd /Users/reehan/Desktop/vox/app && swift build 2>&1
```
Expected: Build succeeds.

**Step 5: Commit**

```bash
cd /Users/reehan/Desktop/vox
git add app/Sources/Vox/AppController.swift app/Sources/Vox/VoxApp.swift
git commit -m "feat: wire full pipeline — hotkey → transcribe → clean → insert

Connects all components through AppController state machine.
Menu bar UI shows real-time state (idle/listening/processing).
Comments explain the orchestration pattern used by STT products.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 8: Model Download & First Run Setup

**Context:** The STT model needs to be downloaded before first use. For Moonshine, this means downloading .ort files from HuggingFace. For WhisperKit, it auto-downloads on first init. This task handles model setup so the app works on first launch.

**Files:**
- Create: `app/Sources/Vox/ModelManager.swift`
- Create: `app/scripts/download-model.sh`

**Step 1: Create ModelManager that handles model download and path resolution**

```swift
// app/Sources/Vox/ModelManager.swift
// ============================================================
// ModelManager — Handles model download and path resolution.
//
// STT models are large files (100MB-2GB) that can't be bundled
// in the git repo. They need to be downloaded on first launch.
//
// For Moonshine v2 Medium:
//   - ~250MB of .ort files from HuggingFace
//   - Stored in ~/Library/Application Support/Vox/models/
//
// For WhisperKit:
//   - Auto-downloads via HuggingFace Hub on first init
//   - Stores in ~/Library/Caches/huggingface/
//
// This manager checks if models exist, downloads if needed,
// and provides the path to the transcriber.
// ============================================================

import Foundation

struct ModelManager {

    /// Directory where Vox stores its models
    static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Vox/models")
    }

    /// Check if the model files exist
    static func isModelDownloaded(modelName: String = "medium-streaming-en") -> Bool {
        let modelDir = modelsDirectory.appendingPathComponent(modelName)
        // Check for the key file that indicates model is present
        return FileManager.default.fileExists(
            atPath: modelDir.appendingPathComponent("tokenizer.bin").path
        )
    }

    /// Get the path to the model directory
    static func modelPath(modelName: String = "medium-streaming-en") -> String {
        return modelsDirectory
            .appendingPathComponent(modelName)
            .path
    }

    /// Create the models directory if it doesn't exist
    static func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )
    }
}
```

**Step 2: Create a model download script**

Create `app/scripts/download-model.sh`:

```bash
#!/bin/bash
# ============================================================
# download-model.sh — Download Moonshine v2 model files
#
# Downloads the medium-streaming-en model from HuggingFace.
# This needs to run once before the first app launch.
#
# The model files are ONNX Runtime format (.ort) — a portable
# neural network format that runs on CPU/GPU across platforms.
#
# Usage: ./scripts/download-model.sh
# ============================================================

set -euo pipefail

MODEL_NAME="medium-streaming-en"
MODELS_DIR="$HOME/Library/Application Support/Vox/models/$MODEL_NAME"

echo "Downloading Moonshine v2 $MODEL_NAME model..."
echo "Destination: $MODELS_DIR"

# Create directory
mkdir -p "$MODELS_DIR"

# Base URL for HuggingFace model files
BASE_URL="https://huggingface.co/UsefulSensors/moonshine-v2/resolve/main/$MODEL_NAME"

# List of model files needed for streaming inference
FILES=(
    "frontend.ort"
    "encoder.ort"
    "adapter.ort"
    "cross_kv.ort"
    "decoder_kv.ort"
    "streaming_config.json"
    "tokenizer.bin"
)

for file in "${FILES[@]}"; do
    if [ -f "$MODELS_DIR/$file" ]; then
        echo "  ✓ $file (already exists)"
    else
        echo "  ↓ Downloading $file..."
        curl -L -o "$MODELS_DIR/$file" "$BASE_URL/$file"
    fi
done

echo ""
echo "✓ Model downloaded successfully to $MODELS_DIR"
echo "  You can now run the Vox app."
```

**Step 3: Make the script executable and commit**

Run:
```bash
chmod +x /Users/reehan/Desktop/vox/app/scripts/download-model.sh
```

```bash
cd /Users/reehan/Desktop/vox
git add app/Sources/Vox/ModelManager.swift app/scripts/download-model.sh
git commit -m "feat: add model download manager and setup script

ModelManager handles model path resolution and existence checks.
download-model.sh fetches Moonshine v2 from HuggingFace on first setup.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 9: End-to-End Integration Test

**Context:** This is the moment of truth — speak into the mic, see text appear in another app.

**Step 1: Download the model (if using Moonshine)**

Run:
```bash
cd /Users/reehan/Desktop/vox/app && bash scripts/download-model.sh
```
Expected: Model files download to `~/Library/Application Support/Vox/models/`

**Step 2: Build the app**

Run:
```bash
cd /Users/reehan/Desktop/vox/app && swift build 2>&1
```
Expected: Build succeeds.

**Step 3: Create an app bundle for proper macOS integration**

Run the following to wrap the binary in a .app bundle (needed for menu bar, permissions):
```bash
APP_NAME="Vox"
BUILD_DIR="/Users/reehan/Desktop/vox/app/.build/debug"
BUNDLE_DIR="/Users/reehan/Desktop/vox/app/build/${APP_NAME}.app"

mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${BUNDLE_DIR}/Contents/Resources"

# Copy binary
cp "${BUILD_DIR}/${APP_NAME}" "${BUNDLE_DIR}/Contents/MacOS/"

# Copy Info.plist
cp "/Users/reehan/Desktop/vox/app/Sources/Vox/Info.plist" "${BUNDLE_DIR}/Contents/"

# Create PkgInfo
echo -n "APPL????" > "${BUNDLE_DIR}/Contents/PkgInfo"

echo "✓ App bundle created at ${BUNDLE_DIR}"
```

**Step 4: Run the app**

Run:
```bash
open /Users/reehan/Desktop/vox/app/build/Vox.app
```

**Step 5: Test the full pipeline**

1. Look for the microphone icon in the menu bar
2. Click it — verify the panel appears with "Ready" status
3. Open TextEdit or any text editor
4. Press Cmd+Shift+V — status should change to "Listening..."
5. Speak a sentence: "Hello, this is a test of the Vox speech to text application"
6. Press Cmd+Shift+V again — status should change to "Processing..." then "Inserting..."
7. Verify the transcribed text appears in TextEdit
8. Verify filler words (if any) were removed

**Step 6: Grant Accessibility permission if prompted**

If text doesn't insert, the app may need Accessibility permission:
1. Go to System Settings > Privacy & Security > Accessibility
2. Add Vox.app
3. Try again

**Step 7: Debug if needed**

If issues:
- Check Console.app for error messages from Vox
- Verify microphone permission was granted
- Try with a simpler model (tinyStreaming) if medium is too slow
- Check that the model files exist in ~/Library/Application Support/Vox/models/

**Step 8: Commit working state**

```bash
cd /Users/reehan/Desktop/vox
git add -A
git commit -m "feat: end-to-end pipeline working — speak → transcribe → insert

Full pipeline verified: global hotkey activates mic, Moonshine v2
transcribes speech, TextProcessor removes filler words, text is
inserted into active app via clipboard paste.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 10: README and Architecture Documentation

**Files:**
- Create: `README.md`
- Create: `docs/architecture.md`

**Step 1: Write the README**

The README is the first thing people see. It should communicate:
1. What Vox is and why it was built (the narrative)
2. How to install and run it
3. How it works (link to architecture doc and visualizer)

Create `README.md` at the project root with:
- Project title and one-line description
- The narrative: "I rebuilt Wispr Flow to understand what makes great dictation software great"
- Quick start (prerequisites, model download, build, run)
- Architecture overview (link to docs/architecture.md)
- Interactive visualizer (link to visualizer/)
- Key findings / what I learned
- Sources and acknowledgments
- License (MIT)

**Step 2: Write the architecture doc**

Create `docs/architecture.md` with:
- The 5-stage pipeline diagram (from the design doc)
- Explanation of each stage with code references
- Model comparison table
- "Model vs. Product Engineering" analysis
- How Wispr Flow does it differently (and why)

**Step 3: Commit**

```bash
cd /Users/reehan/Desktop/vox
git add README.md docs/architecture.md
git commit -m "docs: add README and architecture documentation

Explains the project narrative, setup instructions, and the
5-stage STT pipeline with model vs. product engineering analysis.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Execution Notes

### Risk Mitigation

1. **Moonshine macOS XCFramework** — If the SPM package doesn't build for macOS, immediately switch to WhisperKit (Task 3, Step 3b). Don't waste time trying to build Moonshine from source on Day 1.

2. **Accessibility permission** — The app MUST be run as a .app bundle (not raw binary) for Accessibility permission to work. Task 9 creates this bundle.

3. **Audio format mismatch** — If Moonshine's MicTranscriber doesn't handle the mic's native sample rate, we'll need to add AVAudioConverter for resampling. WhisperKit handles this internally.

4. **Swift 6 concurrency** — Swift 6 has strict concurrency checking. The code uses `@MainActor` annotations and `Task {}` blocks to satisfy the compiler. If build fails on concurrency issues, add `@preconcurrency import` or relax checking with `-strict-concurrency=minimal` in Package.swift.

### What Each File Does (Quick Reference)

| File | Purpose | Complexity |
|------|---------|------------|
| `VoxApp.swift` | App entry point, menu bar UI | Low |
| `AppController.swift` | Pipeline orchestrator, state machine | Medium |
| `Transcriber.swift` | STT model integration (Moonshine or WhisperKit) | High |
| `TextProcessor.swift` | Filler word removal (regex) | Low |
| `TextInserter.swift` | Clipboard paste into active app | Medium |
| `HotkeyManager.swift` | Global hotkey registration | Low |
| `ModelManager.swift` | Model download and path management | Low |
