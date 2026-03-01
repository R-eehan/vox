// ModelManager.swift — Handles model storage path and status
// ============================================================
//
// STT models are large files (100MB-2GB) that can't be bundled
// in the git repo. They need to be downloaded on first launch.
//
// For WhisperKit (our engine):
//   - Auto-downloads via HuggingFace Hub on first init
//   - Default cache: ~/Library/Caches/huggingface/
//   - We override to: ~/Library/Application Support/Vox/models/
//     so the user can find and manage model files easily
//   - large-v3-turbo is ~1-2 GB
// ============================================================

import Foundation

struct ModelManager {

    /// Directory where Vox stores its WhisperKit models.
    /// We use Application Support (not Caches) so macOS doesn't
    /// automatically purge the files under storage pressure.
    static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Vox/models")
    }

    /// The model variant we use.
    static let modelName = "large-v3-turbo"

    /// Check if a WhisperKit model directory exists at our storage path.
    static func isModelDownloaded() -> Bool {
        let modelDir = modelsDirectory
        guard FileManager.default.fileExists(atPath: modelDir.path) else {
            return false
        }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: modelDir,
            includingPropertiesForKeys: nil
        )) ?? []
        return !contents.isEmpty
    }

    /// Create the models directory if it doesn't exist.
    static func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )
    }
}
