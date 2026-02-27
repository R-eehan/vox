# Vox — Design Document

**Date:** 2026-02-28
**Author:** Reehan Ahmed + Claude
**Status:** Approved

---

## 1. What We're Building

**Vox** is a learning project that produces three deliverables:

1. **Vox App** — A native macOS speech-to-text menu bar app built in Swift
2. **Vox Pipeline Visualizer** — An interactive web-based explainer that shows how STT works, stage by stage
3. **Blog post** — "I Rebuilt Wispr Flow to Understand What Makes Great Dictation Software Great"

### The Narrative

The app is the lab. The visualizer is the presentation. The blog is the story.

The core question this project answers: **"Which parts of great dictation software are model capabilities, and which are product engineering?"**

This is NOT a product that fills a market gap. 12+ open-source STT apps already exist. This is a PM dissecting a product by rebuilding it — and the publishable angle is the analysis, not the code.

### Motivation (Force-Ranked)

1. **Learn** — Understand how STT products work end-to-end (audio capture → model inference → text insertion)
2. **Ship** — Create a working tool that could be proposed to Whatfix IT as an auditable alternative to vendor STT tools
3. **Portfolio** — Publish learnings as blog + LinkedIn. Narrative: "PM rebuilds a product he uses daily to understand what makes great dictation software great."

---

## 2. Research Findings

### 2.1 The STT Model Landscape (February 2026)

The landscape has shifted dramatically. **Whisper is no longer the gold standard for streaming.**

| Model | Params | WER | M3 Latency | Streaming? | License |
|-------|--------|-----|------------|-----------|---------|
| **Moonshine v2 Medium** | 245M | **6.65%** | **258ms** | Native | MIT (EN) |
| Moonshine v2 Small | 123M | 7.84% | 148ms | Native | MIT (EN) |
| WhisperKit (Turbo) | 809M | 7.75% | Real-time (chunked) | Via VAD | MIT |
| Whisper large-v3 (whisper.cpp) | 1.55B | 7.4% | 11,286ms | No (30s window) | MIT |
| Parakeet-TDT 0.6B | 600M | ~8% | Fast | Native | CC-BY-4.0 |
| Apple SpeechAnalyzer | Unknown | ~7.4% | Real-time | Native | Proprietary |
| Vosk | ~50MB | ~15-20% | Real-time | Native | Apache 2.0 |
| faster-whisper | 809M | 7.75% | Slow (CPU only) | Chunked | MIT |

**Key insight:** Moonshine v2 Medium beats Whisper large-v3 on accuracy (6.65% vs 7.4%) while being 43x faster and 6x smaller. It was purpose-built for streaming on edge devices.

**Models NOT recommended for macOS:**
- faster-whisper — No Metal support, CPU-only on Mac
- Vosk — Legacy, accuracy far below modern alternatives, uncertain Apple Silicon support
- Deepgram Nova — Cloud-only, no local mode

**Moonshine v2 licensing:**
- English models: MIT (fully open, commercial OK)
- Non-English models (8 languages): Moonshine Community License (free <$1M revenue, paid above)

### 2.2 Competitive Landscape

| Project | Language | Stars | Text Insertion | Key Feature |
|---------|----------|-------|----------------|-------------|
| **Handy** | Rust (Tauri) | 16.3k | Clipboard paste | Most starred OSS STT app |
| **VoiceInk** | Swift | 4k | Accessibility API + clipboard | Per-app config, context-aware |
| **OpenWhispr** | TypeScript (Electron) | 1.4k | Platform-specific | Cross-platform, multi-model |
| **OpenSuperWhisper** | Swift | 650 | Clipboard paste | Multi-mic, Asian language support |
| **whisper-writer** | Python | 1k | pynput (char-by-char) | Simple, minimal |
| **Buzz** | Python | 18k | N/A (file transcription) | Not a dictation tool |

**Distribution:** Swift-native and Tauri/Rust dominate. No Go-based STT app exists. Python apps are transcription-focused, not real-time dictation.

### 2.3 Commercial Products Teardown

#### Wispr Flow
- **Architecture:** Fully cloud-based. Multi-step pipeline: audio capture (local) → screen context capture (local) → ASR inference (cloud, <200ms) → LLM post-processing via fine-tuned Llama on Baseten/AWS (cloud, <200ms)
- **Total latency:** <700ms p99 end-to-end
- **Revenue:** $10M+ (as of mid-2025, likely higher now)
- **Funding:** $81M total ($30M Series A from Menlo Ventures, $25M extension from Notable Capital)
- **Languages:** 100+ with auto-detection, 7 with model parity
- **Pricing:** Free (2k words/week), Pro $15/month, Enterprise $24/user/month
- **Secret sauce:** NOT the transcription model — it's the LLM post-processing. Personalized Llama models that learn your writing style, read your screen context, and format output accordingly.
- **Privacy concern:** Sends voice recordings + screenshots to cloud servers (OpenAI, Meta). "Privacy Mode" available but data still leaves device during processing.

#### Monologue by Every
- Same cloud-based playbook as Wispr Flow
- Built by Naveen Naidu (Every's EIR)
- 100+ languages, screen context, style learning
- $10/month standalone, $30/month with Every subscription
- Claims zero data retention but audio + screenshots leave device

#### The Key Product Insight

> **The accuracy gap between local and cloud STT models has nearly closed** (Moonshine v2: 6.65% WER vs cloud services: 5-7% WER). The remaining perceived quality gap is almost entirely from **LLM post-processing** — filler removal, grammar correction, context-aware formatting. No local-first product does this well with a local LLM yet. That's the open opportunity.

**What Wispr Flow sells isn't transcription — it's editing.** The model does 95% of the work. The product does the last 5% that makes it feel like magic.

### 2.4 Text Insertion Approaches

| Approach | How | Used By | Pros | Cons |
|----------|-----|---------|------|------|
| **Clipboard paste** (Cmd+V sim) | Save clipboard → write text → simulate Cmd+V → restore | Wispr Flow, VoiceInk, Handy, most apps | Works everywhere, fast, handles Unicode | Destroys clipboard (must save/restore) |
| **CGEvent keystroke sim** | Simulate keyboard events character-by-character | whisper-writer | No clipboard touch | Slow for long text, visible typing |
| **AXUIElement** | Direct text insertion via Accessibility API | VoiceInk (for reading) | Instant, can read context | Not all apps expose AX properly |
| **Input Method Kit** | Register as macOS input source | macOS native Dictation | No Accessibility permission needed | IMK is notoriously buggy, unnatural UX |

**Decision:** Clipboard paste as primary. Same as the entire market.

**Critical finding:** An STT app that inserts text into other apps **cannot be distributed on the Mac App Store** (requires Accessibility permission, blocked in sandbox). Must distribute outside the store — same as Wispr Flow and SuperWhisper.

### 2.5 Language Choice Research

| Capability | Swift | Rust | Go | Python |
|-----------|-------|------|-----|--------|
| Text insertion | Native | FFI (good crates) | FFI (thin ecosystem) | PyObjC |
| Audio capture | AVAudioEngine (native) | cpal + FFI | cgo (manual) | sounddevice |
| Menu bar app | MenuBarExtra / NSStatusItem | Tauri / cacao | menuet / systray | rumps |
| Global hotkey | KeyboardShortcuts | tauri-plugin / FFI | robotgo / cgo | pynput |
| STT model integration | WhisperKit / whisper.cpp | whisper-rs | whisper.cpp (cgo) | faster-whisper |
| macOS API coverage | 100% | ~70% | ~40% | ~85% |
| Real-world STT apps | VoiceInk, SuperWhisper | Handy (Tauri) | None | Dictator |

**Decision:** Swift. Native macOS, best system integration, strongest portfolio signal.

---

## 3. Architecture

### 3.1 Vox App Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    macOS Menu Bar                         │
│  [🎙 Vox]  ← MenuBarExtra (SwiftUI)                     │
│   ├── Status indicator (idle / listening / processing)   │
│   ├── Model selector (Moonshine v2 / WhisperKit)         │
│   └── Quit                                               │
└──────────────┬──────────────────────────────────────────┘
               │ Global Hotkey (Cmd+Shift+V or customizable)
               ▼
┌──────────────────────────┐
│    1. Audio Capture       │  AVAudioEngine → 16kHz mono Float32
│    (AudioCapture.swift)   │  Mic permission via Info.plist
└──────────┬───────────────┘
           │ PCM audio buffers
           ▼
┌──────────────────────────┐
│    2. Voice Activity      │  Detect speech start/stop
│    Detection (VAD)        │  Moonshine v2 has built-in streaming VAD
└──────────┬───────────────┘
           │ Speech segments only
           ▼
┌──────────────────────────┐
│    3. Model Inference     │  Moonshine v2 Medium (245M params)
│    (Transcriber.swift)    │  Native streaming, 258ms latency
│                           │  Fallback: WhisperKit (Turbo)
└──────────┬───────────────┘
           │ Raw transcription text
           ▼
┌──────────────────────────┐
│    4. Text Cleanup        │  Regex-based filler removal
│    (TextProcessor.swift)  │  "um", "uh", "like" → removed
│                           │  Basic punctuation cleanup
│                           │  NO LLM post-processing (deliberate)
└──────────┬───────────────┘
           │ Cleaned text
           ▼
┌──────────────────────────┐
│    5. Text Insertion      │  Save clipboard → write text →
│    (TextInserter.swift)   │  simulate Cmd+V → restore clipboard
│                           │  Requires Accessibility permission
└──────────────────────────┘
```

### 3.2 Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Language** | Swift + SwiftUI | Native macOS, best system integration, strongest portfolio signal |
| **Primary model** | Moonshine v2 Medium | 6.65% WER, 258ms latency, native streaming, MIT, smallest footprint |
| **Fallback model** | WhisperKit (Whisper Turbo) | Battle-tested Swift package if Moonshine hits integration issues |
| **Text insertion** | Clipboard paste simulation | Industry standard, works everywhere, same as Wispr Flow |
| **Global hotkey** | KeyboardShortcuts (Sindre Sorhus) | Best Swift library, SwiftUI integration, actively maintained |
| **Audio capture** | AVAudioEngine | Standard macOS audio API, native Swift |
| **VAD** | Moonshine v2 built-in | Native streaming architecture includes VAD |
| **No LLM post-processing** | Deliberate omission | Blog talking point: "Here's the gap between raw model output and Wispr's polished output" |
| **Menu bar only** | LSUIElement = true | No Dock icon, lives in menu bar like Wispr Flow |
| **Distribution** | Outside App Store | Accessibility API requires non-sandboxed app |

### 3.3 Permissions Required

1. **Microphone** — `NSMicrophoneUsageDescription` in Info.plist
2. **Accessibility** — Required for clipboard paste simulation to other apps. User must grant in System Settings > Privacy & Security > Accessibility.

### 3.4 Vox Pipeline Visualizer Architecture

**What:** Standalone web page showing the STT pipeline interactively.

**Tech:** Vanilla HTML/CSS/JS + WebAudio API + Canvas

**Two modes:**
- **Demo mode** (default): Pre-recorded audio walks through the pipeline with animations
- **Live mode**: User speaks into browser mic, sees real waveform + VAD, simulated model output with realistic timing

**Five interactive stages:**

| Stage | What the user sees | The insight |
|-------|-------------------|-------------|
| 1. Audio Capture | Live waveform visualization (WebAudio) | "Sound is just numbers — 16,000 pressure samples per second" |
| 2. VAD | Waveform with speech regions highlighted, silence filtered | "First engineering challenge: when are you actually talking?" |
| 3. Model Inference | Spectrogram → tokens → text animation | "The model handles 95% of the work. This is what Wispr's $81M does NOT buy." |
| 4. Text Cleanup | Before/after: raw text with "ums" vs. cleaned. Toggle filler words. | "Product engineering begins here. This is the 'last 5%' gap." |
| 5. Text Insertion | Simulated text appearing in a text field. Clipboard animation. | "The invisible UX: how text gets from the model to your email" |

**Design requirements:**
- Top-tier design quality — NOT generic AI slop
- Design exploration phase: Google Stitch for variants, ui-ux-pro-max skill for build
- Dark theme, clean typography, generous whitespace
- Smooth animations (CSS transitions + requestAnimationFrame)
- Mobile-responsive (for LinkedIn/blog sharing)
- Embeddable as iframe in blog

### 3.5 Blog Structure

**Title:** "I Rebuilt Wispr Flow to Understand What Makes Great Dictation Software Great"

1. **The problem** — I use Wispr Flow daily. It's magical. I wanted to understand why.
2. **The pipeline** — How STT actually works (embedded interactive visualizer)
3. **What the model gives you** — Raw transcription quality. Before/after examples.
4. **What product engineering adds** — VAD, filler removal, text insertion, latency.
5. **Where Wispr Flow's magic lives** — Cloud LLM post-processing, context awareness, personalization. The gap.
6. **What I learned** — Product insights. Model vs. product. Commoditized vs. defensible.
7. **Try it yourself** — Links to repo + interactive visualizer.

---

## 4. Project Structure

```
vox/
├── app/                          # Swift macOS app (Xcode project)
│   ├── Vox/
│   │   ├── VoxApp.swift              # App entry point, menu bar setup
│   │   ├── AudioCapture.swift        # Mic input, format conversion (16kHz mono)
│   │   ├── Transcriber.swift         # Moonshine v2 integration
│   │   ├── TextProcessor.swift       # Filler word removal, punctuation
│   │   ├── TextInserter.swift        # Clipboard paste into active app
│   │   ├── HotkeyManager.swift       # Global hotkey registration
│   │   └── Views/
│   │       ├── MenuBarView.swift     # Menu bar UI
│   │       └── StatusView.swift      # Recording indicator
│   └── Vox.xcodeproj
├── visualizer/                   # Interactive pipeline explainer
│   ├── index.html                    # Main page
│   ├── style.css                     # Styling + animations
│   ├── js/
│   │   ├── pipeline.js               # Stage orchestration
│   │   ├── waveform.js               # WebAudio waveform renderer
│   │   ├── vad.js                    # VAD visualization
│   │   └── animations.js             # Stage transition animations
│   └── assets/
│       └── samples/                  # Pre-recorded audio samples
├── docs/
│   ├── plans/
│   │   └── 2026-02-28-vox-design.md  # This document
│   ├── architecture.md               # Technical architecture with diagrams
│   ├── teardown.md                   # Model vs. product analysis
│   └── sources.md                    # All research sources
├── blog/
│   └── draft.md                      # Blog post draft
└── README.md                         # Project overview + narrative
```

---

## 5. Build Plan Overview

### Day 1: Vox App
1. Set up Xcode project with SwiftUI menu bar app
2. Integrate Moonshine v2 (or WhisperKit fallback)
3. Implement audio capture → model inference → text output
4. Add text insertion (clipboard paste)
5. Add global hotkey
6. Add basic filler word cleanup
7. Test end-to-end: speak → text appears in active app

### Day 2: Interactive Visualizer
1. Design exploration (Google Stitch, reference research)
2. Build HTML/CSS structure with stage cards
3. Implement WebAudio waveform visualization
4. Build stage-by-stage animation system
5. Add demo mode with pre-recorded samples
6. Add live mode (real waveform, simulated inference)
7. Polish design, test responsiveness

### End of Day 2: Blog Draft
- Structured draft based on build learnings
- Embedded visualizer reference
- Reehan refines and publishes

---

## 6. Sources

### STT Models
- [Moonshine v2 Paper (arXiv)](https://arxiv.org/abs/2602.12241)
- [Moonshine GitHub](https://github.com/moonshine-ai/moonshine)
- [Pete Warden: Announcing Moonshine Voice](https://petewarden.com/2026/02/13/announcing-moonshine-voice/)
- [WhisperKit GitHub](https://github.com/argmaxinc/WhisperKit)
- [WhisperKit Argmax Blog](https://www.argmaxinc.com/blog/whisperkit)
- [whisper.cpp GitHub](https://github.com/ggml-org/whisper.cpp)
- [Parakeet MLX Port](https://github.com/senstella/parakeet-mlx)
- [Northflank: Best Open Source STT 2026 Benchmarks](https://northflank.com/blog/best-open-source-speech-to-text-stt-model-in-2026-benchmarks)
- [Voxtral 3B (Mistral)](https://mistral.ai/news/voxtral)
- [Apple SpeechAnalyzer (WWDC 2025)](https://developer.apple.com/documentation/speech/speechanalyzer)

### Competitive Landscape
- [VoiceInk GitHub](https://github.com/Beingpax/VoiceInk)
- [Handy GitHub](https://github.com/cjpais/Handy)
- [OpenWhispr GitHub](https://github.com/HeroTools/open-whispr)
- [OpenSuperWhisper GitHub](https://github.com/Starmel/OpenSuperWhisper)
- [Buzz GitHub](https://github.com/chidiwilliams/buzz)
- [whisper-writer GitHub](https://github.com/savbell/whisper-writer)
- [Moonshine Note Taker GitHub](https://github.com/moonshine-ai/MoonshineNoteTaker)

### Commercial Products
- [Wispr Flow Technical Challenges](https://wisprflow.ai/post/technical-challenges)
- [Wispr Flow on Baseten (Architecture)](https://www.baseten.co/resources/customers/wispr-flow/)
- [TechCrunch: Wispr raises $30M](https://techcrunch.com/2025/06/24/wispr-flow-raises-30m-from-menlo-ventures-for-its-ai-powered-dictation-app/)
- [Wispr Flow Pricing](https://wisprflow.ai/pricing)
- [Wispr Flow Privacy Review](https://www.eesel.ai/blog/wispr-flow-review)
- [GetLatka: Wispr Flow Revenue](https://getlatka.com/companies/wisprflow.ai)
- [Monologue by Every](https://every.to/on-every/introducing-monologue-effortless-voice-dictation)
- [Monologue Website](https://www.monologue.to/)
- [Superwhisper](https://superwhisper.com/)

### macOS System Integration
- [Apple AXUIElement Documentation](https://developer.apple.com/documentation/applicationservices/axuielement)
- [Text Insertion: Two Ways (Itsuki)](https://levelup.gitconnected.com/swift-macos-insert-text-to-other-active-applications-two-ways-9e2d712ae293)
- [Auto-Type on macOS (Igor Kulman)](https://blog.kulman.sk/implementing-auto-type-on-macos/)
- [KeyboardShortcuts (Sindre Sorhus)](https://github.com/sindresorhus/KeyboardShortcuts)
- [HotKey (Sam Soffes)](https://github.com/soffes/HotKey)
- [Apple MenuBarExtra Documentation](https://developer.apple.com/documentation/swiftui/menubarextra)
- [Accessibility Permission in Sandbox](https://developer.apple.com/forums/thread/707680)
- [Wispr Flow: Text Not Pasting](https://docs.wisprflow.ai/articles/4481008749-text-not-pasting-or-inserting)
- [Dictator: Python macOS STT App](https://albertsikkema.com/python/development/macos/productivity/local-ai/2026/01/17/dictator-speech-to-text-macos-app.html)
- [IMKit Bugs Documentation](https://gist.github.com/ShikiSuen/73b7a55526c9fadd2da2a16d94ec5b49)
