// app/Package.swift
// ============================================================
// Package manifest for Vox — a local-first macOS STT app.
//
// Dependencies:
// - HotKey: Global hotkey registration (wraps Carbon RegisterEventHotKey)
// - WhisperKit: Swift-native Whisper implementation for Apple Silicon.
//
// NOTE: We tried Moonshine v2 first (preferred for its native streaming
// and lower latency) but its XCFramework has linking issues with SPM
// when building without full Xcode (CLI tools only). The macOS slice
// exists but SPM doesn't properly link the binary target symbols.
// See docs/plans/2026-02-28-vox-design.md for the full model comparison.
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
            path: "Sources/Vox",
            exclude: ["Info.plist"]
        ),
    ]
)
