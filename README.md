# Vox

**A native macOS speech-to-text menu bar app — built to understand what makes great dictation software great.**

Vox captures your speech, transcribes it locally using WhisperKit (OpenAI's Whisper on Apple Silicon), cleans up filler words, and inserts the text wherever your cursor is. No cloud. No subscription. No data leaves your machine.

This is a learning project. The goal isn't to compete with Wispr Flow — it's to rebuild one from scratch and understand which parts are model capabilities and which are product engineering.

## Quick Start

### Prerequisites

- macOS 14+ (Sonoma or later)
- Apple Silicon Mac (M1/M2/M3/M4/M5)
- Swift 6.0+ (comes with Xcode Command Line Tools)
- ~2 GB disk space for the WhisperKit model (downloaded on first launch)

### Build & Run

```bash
# Clone the repo
git clone https://github.com/reehan/vox.git
cd vox

# Build the app
cd app && swift build

# Create the app bundle (needed for menu bar + permissions)
APP_NAME="Vox"
BUILD_DIR=".build/debug"
BUNDLE_DIR="build/${APP_NAME}.app"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS" "${BUNDLE_DIR}/Contents/Resources"
cp "${BUILD_DIR}/${APP_NAME}" "${BUNDLE_DIR}/Contents/MacOS/"
cp "Sources/Vox/Info.plist" "${BUNDLE_DIR}/Contents/"
echo -n "APPL????" > "${BUNDLE_DIR}/Contents/PkgInfo"

# Launch
open "build/Vox.app"
```

On first launch, WhisperKit downloads the `large-v3-turbo` model (~1-2 GB). You'll see "Loading model..." in the menu bar panel. Subsequent launches are instant.

### Usage

1. Look for the microphone icon in the macOS menu bar
2. Press **Cmd+Shift+V** to start dictation
3. Speak naturally
4. Press **Cmd+Shift+V** again to stop — your text appears where your cursor is

### Permissions

Vox needs two macOS permissions:

- **Microphone** — prompted automatically on first use
- **Accessibility** — required for pasting text into other apps. Go to System Settings > Privacy & Security > Accessibility and add Vox

## How It Works

The pipeline has 5 stages:

```
[Hotkey] → [Audio Capture] → [Model Inference] → [Text Cleanup] → [Text Insertion]
   ⌘⇧V      AVAudioEngine      WhisperKit         Regex filler     Clipboard paste
                                 large-v3-turbo     word removal     + Cmd+V sim
```

See [docs/architecture.md](docs/architecture.md) for the detailed breakdown.

## Architecture

| File | Purpose |
|------|---------|
| `VoxApp.swift` | App entry point, menu bar UI |
| `AppController.swift` | Pipeline orchestrator, state machine |
| `Transcriber.swift` | WhisperKit model integration |
| `TextProcessor.swift` | Filler word removal (regex) |
| `TextInserter.swift` | Clipboard paste into active app |
| `HotkeyManager.swift` | Global hotkey registration |
| `ModelManager.swift` | Model path management |

## What I Learned

**Model engineering vs. product engineering:** The STT model gets you 90% of the way. The last 10% — the part that makes Wispr Flow feel magical — is product engineering:

- **Filler word removal**: We use regex. Wispr Flow uses a fine-tuned LLM that understands context ("I mean" as filler vs. meaningful).
- **Text formatting**: We output raw text. Wispr Flow formats based on which app you're typing in (Slack vs. email vs. code editor).
- **Writing style**: We don't touch style. Wispr Flow adapts to your personal writing voice.

The gap between "technically working" and "delightful product" is enormous — and it's almost entirely product engineering, not model improvement.

## Model Choice

We tried Moonshine v2 first (preferred — native streaming, 258ms latency, 6.65% WER) but its XCFramework has SPM linking issues without full Xcode. Fell back to WhisperKit with `large-v3-turbo` — slightly higher latency but battle-tested on macOS with CoreML + Apple Neural Engine acceleration.

See [docs/plans/2026-02-28-vox-design.md](docs/plans/2026-02-28-vox-design.md) for the full model comparison.

## License

MIT

## Acknowledgments

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax — Swift-native Whisper for Apple Silicon
- [HotKey](https://github.com/soffes/HotKey) by Sam Soffes — Global hotkey library
- [Moonshine](https://github.com/moonshine-ai/moonshine-swift) by Moonshine AI — Streaming STT (attempted, linking issues)
- [Wispr Flow](https://www.wispr.com/) — The product that inspired this project
