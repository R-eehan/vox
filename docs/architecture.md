# Vox Architecture

## The 5-Stage Pipeline

Every dictation product — from Apple Dictation to Wispr Flow — follows the same fundamental pipeline. Vox implements each stage explicitly so you can see how it works.

```
┌──────────┐    ┌───────────────┐    ┌─────────────────┐    ┌──────────────┐    ┌────────────────┐
│  Hotkey   │───>│ Audio Capture │───>│ Model Inference │───>│ Text Cleanup │───>│ Text Insertion │
│  ⌘⇧V     │    │ AVAudioEngine │    │ WhisperKit      │    │ Regex filler │    │ Clipboard +    │
│           │    │ 48kHz Float32 │    │ large-v3-turbo  │    │ word removal │    │ Cmd+V simulate │
└──────────┘    └───────────────┘    └─────────────────┘    └──────────────┘    └────────────────┘
```

## Stage 1: Global Hotkey (`HotkeyManager.swift`)

**What it does:** Registers Cmd+Shift+V as a system-wide hotkey using the HotKey library.

**Why it matters:** A dictation tool is useless if activating it is clunky. The user needs to start speaking instantly from any app.

**How it works:** The HotKey library wraps Carbon's `RegisterEventHotKey` API — a legacy API from Classic Mac OS that's deprecated but still the only way to "swallow" a system-wide keystroke.

**Toggle behavior:** First press → start recording. Second press → stop recording, process, insert.

## Stage 2: Audio Capture (`Transcriber.swift`)

**What it does:** Captures microphone audio via AVAudioEngine and accumulates it in a Float32 buffer.

**How it works:**
1. Create an `AVAudioEngine` and access its `inputNode` (the microphone)
2. Install a "tap" — a callback that receives audio chunks as they arrive
3. Accumulate raw PCM samples (Float32, channel 0) in an array
4. When recording stops, pass the entire buffer to the model

**Sample rate:** The Mac's microphone typically runs at 48kHz. WhisperKit resamples to 16kHz internally.

## Stage 3: Model Inference (`Transcriber.swift`)

**What it does:** Runs OpenAI's Whisper model (large-v3-turbo variant) via WhisperKit on Apple Silicon.

**How it works:**
- WhisperKit uses CoreML to run the model on the Apple Neural Engine (ANE)
- The model processes the entire audio buffer at once (batch mode)
- Returns text with timestamps, confidence scores, and word-level timing

**Model details:**
| Property | Value |
|----------|-------|
| Model | large-v3-turbo |
| Parameters | 809M |
| Word Error Rate | ~7.75% |
| Runtime | CoreML (ANE + GPU) |
| Size on disk | ~1-2 GB |
| First-run download | From HuggingFace |

**Why not Moonshine v2?** Moonshine v2 is actually better for this use case — native streaming, 258ms latency, 6.65% WER. But its Swift Package XCFramework has linking issues when building with SPM without full Xcode. The macOS arm64 slice exists but SPM doesn't properly link the binary target's static library symbols. See the design doc for the full comparison.

## Stage 4: Text Cleanup (`TextProcessor.swift`)

**What it does:** Removes filler words ("um", "uh", "you know") from the raw transcription.

**The product engineering gap:** This is where our app and Wispr Flow diverge most dramatically.

| | Vox | Wispr Flow |
|---|---|---|
| **Approach** | Regex pattern matching | Fine-tuned LLM (Llama) on AWS |
| **Latency** | 0ms | ~200ms |
| **Cost** | Free | Cloud inference cost |
| **Context awareness** | None — removes all matches | Understands when "I mean" is filler vs. meaningful |
| **Style adaptation** | None | Adapts to your personal writing style |
| **App awareness** | None | Formats differently for Slack vs. email vs. code |

Our regex will incorrectly remove some meaningful uses of words like "actually" and "I mean." That's the gap between "pattern matching" and "understanding."

## Stage 5: Text Insertion (`TextInserter.swift`)

**What it does:** Inserts the cleaned text into whatever app has focus, wherever the cursor is.

**How every production STT app does this:**
1. Save the current clipboard contents
2. Write our text to the clipboard
3. Simulate Cmd+V via CGEvent (Core Graphics keyboard event)
4. Wait 100ms for the paste to complete
5. Restore the original clipboard

**Why clipboard paste?** Three alternatives exist, and all are worse:
- **AXUIElement (Accessibility API):** Can set text directly, but many apps don't implement it (Electron, contentEditable, custom text engines)
- **CGEvent keystrokes:** Types character-by-character — visibly slow for long text
- **Apple Events:** Deprecated and sandboxed out of most modern apps

Clipboard paste works in 99%+ of apps and is instant. The tradeoff is briefly overwriting the user's clipboard (we save and restore it).

**Requires Accessibility permission** in System Settings. Without it, CGEvent posting to other apps is silently blocked by macOS.

## State Machine (`AppController.swift`)

The AppController orchestrates all five stages:

```
LOADING ─── (model downloaded) ───> IDLE
IDLE ────── (⌘⇧V pressed) ────────> LISTENING
LISTENING ─ (⌘⇧V pressed) ────────> PROCESSING
PROCESSING ─ (transcription done) ─> INSERTING
INSERTING ── (paste complete) ─────> IDLE
ERROR ────── (any failure) ────────> IDLE (after reset)
```

Each state maps to a different menu bar icon and color, giving the user visual feedback about what's happening.
