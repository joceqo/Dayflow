//
//  LocalAnalysisPreferences.swift
//  Dayflow
//
//  User-tunable knobs for how hard the local (Ollama/LM Studio) analysis
//  pipeline hits the machine: how many frames get described per batch, and
//  whether frames are described continuously as they are captured instead
//  of in one burst when the batch closes.
//

import Foundation

enum LocalAnalysisPreferences {
  static let streamingEnabledKey = "llmLocalStreamingAnalysis"
  static let frameSamplesKey = "llmLocalFrameSamples"

  static let defaultFrameSamples = 15
  static let frameSamplesRange = 4...20

  /// Describe frames continuously (~1/min) instead of a burst at batch close.
  static var streamingEnabled: Bool {
    UserDefaults.standard.bool(forKey: streamingEnabledKey)
  }

  static func setStreamingEnabled(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: streamingEnabledKey)
  }

  /// How many screenshots get described per 15-minute batch (local provider only).
  static var frameSamples: Int {
    let stored = UserDefaults.standard.integer(forKey: frameSamplesKey)
    guard stored != 0 else { return defaultFrameSamples }
    return clampFrameSamples(stored)
  }

  static func setFrameSamples(_ value: Int) {
    UserDefaults.standard.set(clampFrameSamples(value), forKey: frameSamplesKey)
  }

  static func clampFrameSamples(_ value: Int) -> Int {
    min(max(value, frameSamplesRange.lowerBound), frameSamplesRange.upperBound)
  }
}
