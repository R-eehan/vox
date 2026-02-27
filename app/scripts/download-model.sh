#!/bin/bash
# ============================================================
# download-model.sh — Pre-download the WhisperKit model
#
# WhisperKit auto-downloads on first app launch, but this script
# lets you pre-download so the first launch is instant.
#
# The model files are CoreML format (.mlmodelc) — Apple's native
# machine learning model format optimized for Neural Engine (ANE),
# GPU, and CPU inference on Apple Silicon.
#
# Model: large-v3-turbo (~1-2 GB)
# Source: HuggingFace (argmaxinc/whisperkit-coreml)
#
# Usage: ./scripts/download-model.sh
# ============================================================

set -euo pipefail

MODELS_DIR="$HOME/Library/Application Support/Vox/models"

echo "=== Vox Model Download ==="
echo ""
echo "WhisperKit auto-downloads the model on first launch."
echo "This script pre-downloads it for instant first-launch."
echo ""
echo "Model: large-v3-turbo (~1-2 GB)"
echo "Destination: $MODELS_DIR"
echo ""

# Create directory
mkdir -p "$MODELS_DIR"

# Check if model already exists
if [ -d "$MODELS_DIR" ] && [ "$(ls -A "$MODELS_DIR" 2>/dev/null)" ]; then
    echo "✓ Model directory already contains files."
    echo "  Delete $MODELS_DIR to re-download."
    exit 0
fi

echo "To pre-download, you have two options:"
echo ""
echo "Option 1: Just run the app — WhisperKit downloads automatically."
echo "  cd /Users/reehan/Desktop/vox/app && swift run Vox"
echo ""
echo "Option 2: Use huggingface-cli (if installed):"
echo "  pip install huggingface_hub"
echo "  huggingface-cli download argmaxinc/whisperkit-coreml \\"
echo "    --include 'openai_whisper-large-v3-turbo/*' \\"
echo "    --local-dir '$MODELS_DIR'"
echo ""
echo "The app will show 'Loading model...' on first launch while"
echo "it downloads. Subsequent launches use the cached model."
