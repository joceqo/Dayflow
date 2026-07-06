import Foundation

enum LocalEngine: String, CaseIterable, Identifiable, Codable {
  case ollama
  case lmstudio
  case aidock
  case custom

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .ollama: return "Ollama"
    case .lmstudio: return "LM Studio"
    case .aidock: return "aidock"
    case .custom: return "Custom"
    }
  }

  var defaultBaseURL: String {
    switch self {
    case .ollama: return "http://localhost:11434"
    case .lmstudio: return "http://localhost:1234"
    case .aidock: return "http://127.0.0.1:4774"
    case .custom: return "http://localhost:11434"
    }
  }
}

/// aidock (local LLM gateway) conventions: the daemon writes its bearer token
/// to ~/.config/ai-hub/token at first launch. The app is not sandboxed, so we
/// can read it directly instead of making the user copy-paste it.
enum AidockDefaults {
  static var tokenFileURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/ai-hub/token")
  }

  static func readToken() -> String? {
    guard let raw = try? String(contentsOf: tokenFileURL, encoding: .utf8) else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
