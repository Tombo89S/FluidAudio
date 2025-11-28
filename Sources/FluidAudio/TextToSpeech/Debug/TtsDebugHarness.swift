import Foundation
import OSLog

public enum TtsDebugHarness {

    private static let logger = AppLogger(category: "TtsDebugHarness")

    public static func numberedWordsScript(count: Int = 150) -> String {
        guard count > 0 else { return "" }
        return (1...count).map { index in
            String(format: "word%03d", index)
        }
        .joined(separator: " ")
    }

    /// Synthesize a numbered-word script and persist it for manual listening checks.
    /// Requires an initialized `TtSManager` that already loaded Kokoro models (single-model mode supported).
    @discardableResult
    public static func synthesizeNumberedWords(
        using manager: TtSManager,
        outputURL: URL,
        count: Int = 150,
        voiceSpeed: Float = 1.0,
        variantPreference: ModelNames.TTS.Variant? = .tenSecond
    ) async throws -> KokoroSynthesizer.SynthesisResult {
        guard manager.isAvailable else {
            throw TTSError.modelNotFound("TtSManager not initialized. Call initialize() before running harness.")
        }

        let script = numberedWordsScript(count: count)
        let result = try await manager.synthesizeDetailed(
            text: script,
            voiceSpeed: voiceSpeed,
            variantPreference: variantPreference
        )

        let directory = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try result.audio.write(to: outputURL)

        let flattened = result.chunks.flatMap { $0.words }
        if flattened.count != count {
            logger.warning(
                "Chunked word count \(flattened.count) differs from expected \(count); inspect chunk logs for gaps."
            )
        } else {
            for (idx, word) in flattened.enumerated() {
                let expected = String(format: "word%03d", idx + 1)
                if word != expected {
                    logger.warning("Word mismatch at position \(idx): expected \(expected), got \(word)")
                    break
                }
            }
        }

        logger.notice("Numbered-word synthesis saved to \(outputURL.lastPathComponent)")
        return result
    }
}
