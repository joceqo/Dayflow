import Foundation

@MainActor
final class AppDeepLinkRouter {
  enum Action: String {
    case startRecording = "start-recording"
    case stopRecording = "stop-recording"
    case reprocess = "reprocess"

    init?(identifier: String) {
      switch identifier.lowercased() {
      case Self.startRecording.rawValue, "start", "resume":
        self = .startRecording
      case Self.stopRecording.rawValue, "stop", "pause":
        self = .stopRecording
      case Self.reprocess.rawValue, "reanalyze", "retry":
        self = .reprocess
      default:
        return nil
      }
    }
  }

  init() {}

  @discardableResult
  func handle(_ url: URL) -> Bool {
    guard let action = resolveAction(from: url) else {
      print("[DeepLink] Unsupported URL: \(url.absoluteString)")
      return false
    }

    perform(action, url: url)
    return true
  }

  private func resolveAction(from url: URL) -> Action? {
    guard let scheme = url.scheme, scheme.caseInsensitiveCompare("dayflow") == .orderedSame else {
      return nil
    }

    var candidates: [String] = []
    if let host = url.host, !host.isEmpty {
      candidates.append(host)
    }

    let pathComponents = url.path
      .split(separator: "/")
      .map { String($0) }

    candidates.append(contentsOf: pathComponents)

    if candidates.isEmpty {
      if let actionItem = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
        .first(where: { $0.name.lowercased() == "action" }),
        let value = actionItem.value, !value.isEmpty
      {
        candidates.append(value)
      }
    }

    guard let identifier = candidates.first else { return nil }
    return Action(identifier: identifier)
  }

  private func perform(_ action: Action, url: URL) {
    switch action {
    case .startRecording:
      startRecording()
    case .stopRecording:
      stopRecording()
    case .reprocess:
      reprocess(url: url)
    }
  }

  /// `dayflow://reprocess?day=YYYY-MM-DD` re-runs analysis for a whole day;
  /// `dayflow://reprocess?batch=<id>` re-runs a single batch. Both reset the
  /// targeted batches to pending and push them back through the LLM pipeline —
  /// handy for retrying batches that failed when no model backend was reachable.
  private func reprocess(url: URL) {
    let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func value(_ name: String) -> String? {
      queryItems.first { $0.name.lowercased() == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
    }

    if let day = value("day") {
      print("[DeepLink] Reprocessing day \(day)")
      AnalysisManager.shared.reprocessDay(
        day,
        progressHandler: { print("[DeepLink] reprocess \(day): \($0)") },
        completion: { result in
          switch result {
          case .success: print("[DeepLink] reprocess day \(day) done")
          case .failure(let error): print("[DeepLink] reprocess day \(day) failed: \(error.localizedDescription)")
          }
        })
      return
    }

    if let batchParam = value("batch"), let batchId = Int64(batchParam) {
      print("[DeepLink] Reprocessing batch \(batchId)")
      AnalysisManager.shared.reprocessBatch(
        batchId,
        stepHandler: { print("[DeepLink] reprocess batch \(batchId): \($0)") },
        completion: { result in
          switch result {
          case .success: print("[DeepLink] reprocess batch \(batchId) done")
          case .failure(let error): print("[DeepLink] reprocess batch \(batchId) failed: \(error.localizedDescription)")
          }
        })
      return
    }

    print("[DeepLink] reprocess: missing 'day' or 'batch' parameter")
  }

  private func startRecording() {
    guard RecordingControl.currentMode() != .active else {
      print("[DeepLink] Recording already active; ignoring start request")
      return
    }
    RecordingControl.start(reason: "deeplink")
  }

  private func stopRecording() {
    guard RecordingControl.currentMode() != .stopped else {
      print("[DeepLink] Recording already stopped; ignoring stop request")
      return
    }
    RecordingControl.stop(reason: "deeplink")
  }

}
