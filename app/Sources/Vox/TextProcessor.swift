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
