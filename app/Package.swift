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
            path: "Sources/Vox",
            exclude: ["Info.plist"]
        ),
    ]
)
