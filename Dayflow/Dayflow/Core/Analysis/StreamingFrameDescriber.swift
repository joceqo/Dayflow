//
//  StreamingFrameDescriber.swift
//  Dayflow
//
//  Continuous ("streaming") local analysis: instead of describing ~15 frames
//  in one burst when a 15-minute batch closes, describe roughly one frame per
//  minute as screenshots are captured. Descriptions are stored in
//  screenshot_descriptions and consumed by OllamaProvider.transcribeScreenshots
//  at batch time, which then only needs the merge + card-generation calls.
//
//  Only active when the user enables the setting AND the primary provider is
//  the local one (Ollama/LM Studio) — cloud providers don't do per-frame calls.
//

import Foundation

final class StreamingFrameDescriber {
  static let shared = StreamingFrameDescriber()
  private init() {}

  /// Only look at recent, still-unbatched screenshots. Anything older is about
  /// to be picked up by batch processing, which describes frames on the fly.
  private let lookback: TimeInterval = 30 * 60

  /// Max frames described per tick, so catching up after a pause stays gentle.
  private let maxFramesPerTick = 2

  private let stateLock = NSLock()
  private var isRunning = false

  /// Called once a minute from AnalysisManager's timer.
  func tick() {
    guard LocalAnalysisPreferences.streamingEnabled else { return }
    // v2.1.0 a remplacé `LLMProviderType.load()` par le store de routage, et le cas
    // `.ollama` par `.local`. Un store illisible laisse le tick passer son tour :
    // décrire des frames avec un routage inconnu serait pire que ne rien décrire.
    guard (try? LLMProviderRoutingStore.load())?.primary == .local else { return }
    guard tryBeginRun() else { return }

    Task.detached(priority: .utility) { [weak self] in
      guard let self else { return }
      await self.describeNextFrames()
      self.endRun()
    }
  }

  private func tryBeginRun() -> Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    if isRunning { return false }
    isRunning = true
    return true
  }

  private func endRun() {
    stateLock.lock()
    defer { stateLock.unlock() }
    isRunning = false
  }

  private func describeNextFrames() async {
    let store = StorageManager.shared
    let oldest = Int(Date().timeIntervalSince1970 - lookback)

    let candidates = store.fetchScreenshotsAwaitingDescription(since: oldest)
    guard !candidates.isEmpty else { return }

    // Keep the same sampling density as batch processing: one frame every
    // (batch duration / frames per batch), i.e. 60s at the defaults.
    let batchDuration = LLMService.shared.batchingConfig.targetDuration
    let spacing = max(10, Int(batchDuration) / LocalAnalysisPreferences.frameSamples)

    var lastDescribedTs = store.latestDescribedScreenshotTimestamp() ?? 0
    var selected: [Screenshot] = []

    for screenshot in candidates {
      guard screenshot.capturedAt >= lastDescribedTs + spacing else { continue }

      // Skip clearly idle frames; fully idle batches are short-circuited
      // without any LLM anyway (IdleBatchClassifier).
      if let idleSeconds = screenshot.idleSecondsAtCapture,
        idleSeconds >= IdleBatchRules.qualifyingIdleSecondsAtCapture
      {
        continue
      }

      selected.append(screenshot)
      lastDescribedTs = screenshot.capturedAt
      if selected.count >= maxFramesPerTick { break }
    }

    guard !selected.isEmpty else { return }

    let endpoint =
      UserDefaults.standard.string(forKey: "llmLocalBaseURL") ?? "http://localhost:11434"
    let provider = OllamaProvider(endpoint: endpoint)

    for screenshot in selected {
      guard let description = await provider.describeScreenshotForStreaming(screenshot) else {
        continue
      }
      store.saveScreenshotDescription(
        screenshotId: screenshot.id,
        description: description,
        llmModel: provider.savedModelId
      )
      print(
        "[STREAMING] 🖼️ Described screenshot \(screenshot.id) (\(screenshot.capturedDate)) ahead of batch"
      )
    }
  }
}
