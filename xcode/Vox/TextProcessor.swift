// TextProcessor.swift — Cleans up raw transcription output
// ============================================================
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

    private static let fillerPatterns: [(pattern: String, replacement: String)] = [
        // Single-word fillers
        (#"\b[Uu]mm?\b"#, ""),           // "um", "umm", "Um"
        (#"\b[Uu]hh?\b"#, ""),           // "uh", "uhh"
        (#"\b[Ee]rr?\b"#, ""),           // "er", "err"
        (#"\b[Aa]hh?\b"#, ""),           // "ah", "ahh"
        (#"\b[Hh]mm+\b"#, ""),           // "hmm", "hmmm"

        // Multi-word fillers
        (#"\byou know\b"#, ""),           // "you know"
        (#"\bI mean\b"#, ""),             // "I mean" (risky — sometimes meaningful)
        (#"\bkind of\b"#, ""),            // "kind of"
        (#"\bsort of\b"#, ""),            // "sort of"
        (#"\bbasically\b"#, ""),          // "basically"
        (#"\bactually\b"#, ""),           // "actually"
        (#"\bliterally\b"#, ""),          // "literally"

        // "like" as filler
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

        // Step 2: Collapse multiple spaces
        result = result.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )

        // Step 3: Clean up orphaned punctuation
        result = result.replacingOccurrences(
            of: #",\s*,"#,
            with: ",",
            options: .regularExpression
        )

        // Step 4: Trim
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Step 5: Capitalize first letter
        if let firstChar = result.first, firstChar.isLowercase {
            result = firstChar.uppercased() + result.dropFirst()
        }

        return result
    }
}
