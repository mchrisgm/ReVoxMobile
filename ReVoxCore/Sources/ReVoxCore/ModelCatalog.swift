import Foundation

public enum WhisperModelID: String, CaseIterable, Codable, Sendable, Identifiable {
    case tiny, base, small, medium, largeV3 = "large-v3"

    public var id: String { rawValue }
    public var displayName: String { rawValue }        // "tiny" … "large-v3"
}

public struct WhisperModelDescriptor: Sendable, Equatable, Identifiable {
    public let id: WhisperModelID
    public let folderName: String                 // Hub folder in argmaxinc/whisperkit-coreml
    public let approximateBytes: Int64            // decimal, Hub listing 2026-09-02
    public let modelRepo: String                  // "argmaxinc/whisperkit-coreml"
    public let revision: String                   // 40-hex commit SHA of modelRepo the sizes were listed from (never "main")
    public let tokenizerRepo: String              // "openai/whisper-<size>"; large-v3 → "openai/whisper-large-v3"
    public let tokenizerRevision: String          // 40-hex commit SHA of tokenizerRepo
    public let note: String?                      // large-v3: compressed weights Argmax ships for iPhone

    /// Files that must exist under the model root for the model to count as installed (§6.9):
    /// the three Core ML bundles' `coremldata.bin`, the variant `config.json` and the three tokenizer files.
    public var requiredRelativePaths: [String] {
        let variant = "models/\(modelRepo)/\(folderName)"
        let tokenizer = "models/\(tokenizerRepo)"
        return [
            "\(variant)/MelSpectrogram.mlmodelc/coremldata.bin",
            "\(variant)/AudioEncoder.mlmodelc/coremldata.bin",
            "\(variant)/TextDecoder.mlmodelc/coremldata.bin",
            "\(variant)/config.json",
            "\(tokenizer)/tokenizer.json",
            "\(tokenizer)/tokenizer_config.json",
            "\(tokenizer)/config.json",
        ]
    }
}

public struct VADModelDescriptor: Sendable, Equatable {
    public let repo: String                       // "FluidInference/silero-vad-coreml"
    public let subdirectory: String               // "silero-vad-unified-v6.0.0.mlmodelc"
    public let approximateBytes: Int64            // ≈ 950_000 (weight.bin 882 304 + model.mil 25 126 + metadata)

    /// Under the model root: `fluid/Models/silero-vad/<subdirectory>/coremldata.bin`. FluidAudio's tree sits
    /// under its own `fluid` folder because its `Models` differs from WhisperKit's `models` only by case, which
    /// collides on a case-insensitive volume (app `ModelLayout`).
    public var requiredRelativePaths: [String] {
        ["fluid/Models/silero-vad/\(subdirectory)/coremldata.bin"]
    }
}

public struct PocketTTSDescriptor: Sendable, Equatable {
    public let repo: String                       // "FluidInference/pocket-tts-coreml"
    public let languageFolder: String             // "v2.1/english"
    public let approximateBytes: Int64            // ≈ 527_300_000 (ANE placement, fp16, all 26 voices)
    public let offeredVoices: [String]            // ["alba", "azelma", "cosette", "javert"]
}

public struct LicenceNotice: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let licence: String
    public let url: URL
    public let attribution: String?
}

public enum DownloadKind: Sendable, Equatable, Hashable {
    case whisper(WhisperModelID), vad, pocketTTS
}

public struct DownloadDescriptor: Sendable, Equatable {
    public let kind: DownloadKind
    public let expectedBytes: Int64
    public let displayName: String
}

/// R4 catalog. Sizes are decimal bytes recorded from the Hub listing of 2026-09-02; revisions are the commit SHAs
/// `main` resolved to on that date (`GET https://huggingface.co/api/models/<repo>`, field `sha`).
public enum ModelCatalog {
    static let whisperRepo = "argmaxinc/whisperkit-coreml"
    static let whisperRepoRevision = "0f63a7800b00dd0226abd051b906c246e1907482"

    public static let whisperModels: [WhisperModelDescriptor] = [
        WhisperModelDescriptor(id: .tiny, folderName: "openai_whisper-tiny", approximateBytes: 76_600_000,
                               modelRepo: whisperRepo, revision: whisperRepoRevision,
                               tokenizerRepo: "openai/whisper-tiny",
                               tokenizerRevision: "169d4a4341b33bc18d8881c4b69c2e104e1cc0af", note: nil),
        WhisperModelDescriptor(id: .base, folderName: "openai_whisper-base", approximateBytes: 146_700_000,
                               modelRepo: whisperRepo, revision: whisperRepoRevision,
                               tokenizerRepo: "openai/whisper-base",
                               tokenizerRevision: "e37978b90ca9030d5170a5c07aadb050351a65bb", note: nil),
        WhisperModelDescriptor(id: .small, folderName: "openai_whisper-small", approximateBytes: 486_500_000,
                               modelRepo: whisperRepo, revision: whisperRepoRevision,
                               tokenizerRepo: "openai/whisper-small",
                               tokenizerRevision: "973afd24965f72e36ca33b3055d56a652f456b4d", note: nil),
        WhisperModelDescriptor(id: .medium, folderName: "openai_whisper-medium", approximateBytes: 1_528_000_000,
                               modelRepo: whisperRepo, revision: whisperRepoRevision,
                               tokenizerRepo: "openai/whisper-medium",
                               tokenizerRevision: "abdf7c39ab9d0397620ccaea8974cc764cd0953e",
                               note: "Long load time and heat on eligible devices"),
        WhisperModelDescriptor(id: .largeV3, folderName: "openai_whisper-large-v3_947MB", approximateBytes: 948_000_000,
                               modelRepo: whisperRepo, revision: whisperRepoRevision,
                               tokenizerRepo: "openai/whisper-large-v3",
                               tokenizerRevision: "06f233fe06e710322aca913c1bc4249a0d71fce1",
                               note: "Compressed weights Argmax ships for iPhone"),
    ]

    public static let defaultWhisperModel: WhisperModelID = .small

    public static func whisper(_ id: WhisperModelID) -> WhisperModelDescriptor {
        whisperModels.first { $0.id == id }!
    }

    public static let vad = VADModelDescriptor(repo: "FluidInference/silero-vad-coreml",
                                               subdirectory: "silero-vad-unified-v6.0.0.mlmodelc",
                                               approximateBytes: 950_000)

    public static let pocketTTS = PocketTTSDescriptor(repo: "FluidInference/pocket-tts-coreml",
                                                      languageFolder: "v2.1/english",
                                                      approximateBytes: 527_300_000,
                                                      offeredVoices: ["alba", "azelma", "cosette", "javert"])

    public static let licences: [LicenceNotice] = [
        LicenceNotice(id: "whisperkit", name: "WhisperKit", licence: "MIT",
                      url: URL(string: "https://github.com/argmaxinc/WhisperKit")!, attribution: nil),
        LicenceNotice(id: "fluidaudio", name: "FluidAudio", licence: "Apache-2.0",
                      url: URL(string: "https://github.com/FluidInference/FluidAudio")!, attribution: nil),
        LicenceNotice(id: "pocket-tts", name: "pocket-tts Core ML weights", licence: "CC-BY-4.0",
                      url: URL(string: "https://huggingface.co/FluidInference/pocket-tts-coreml")!,
                      attribution: "pocket-tts by Kyutai (https://kyutai.org)"),
        LicenceNotice(id: "silero-vad", name: "Silero VAD", licence: "MIT",
                      url: URL(string: "https://github.com/snakers4/silero-vad")!, attribution: nil),
        LicenceNotice(id: "whisper", name: "Whisper weights (OpenAI)", licence: "MIT",
                      url: URL(string: "https://github.com/openai/whisper")!, attribution: nil),
    ]

    public static func download(for kind: DownloadKind) -> DownloadDescriptor {
        switch kind {
        case .whisper(let id):
            let descriptor = whisper(id)
            return DownloadDescriptor(kind: kind, expectedBytes: descriptor.approximateBytes,
                                      displayName: "Whisper \(id.displayName)")
        case .vad:
            return DownloadDescriptor(kind: kind, expectedBytes: vad.approximateBytes, displayName: "Voice detector")
        case .pocketTTS:
            return DownloadDescriptor(kind: kind, expectedBytes: pocketTTS.approximateBytes, displayName: "pocket-tts voices")
        }
    }

    /// `available >= expected * 1.25 + 200 MB` (ASSUMED rule, §6.9; thresholds re-checked in M7).
    public static func hasRoomToInstall(expectedBytes: Int64, availableBytes: Int64) -> Bool {
        let needed = Int64((Double(expectedBytes) * 1.25).rounded(.up)) + 200_000_000
        return availableBytes >= needed
    }
}
