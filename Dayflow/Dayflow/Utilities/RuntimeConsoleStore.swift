import Darwin
import Foundation

final class RuntimeConsoleStore: ObservableObject {
  struct Entry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let stream: String
    let message: String
  }

  static let shared = RuntimeConsoleStore()

  @Published private(set) var entries: [Entry] = []

  private var didStart = false
  private let outputPipe = Pipe()
  private var sourceBuffer = Data()
  private var originalStdoutFD: Int32 = -1
  private var originalStderrFD: Int32 = -1
  private let maxEntries = 1200

  private init() {}

  func startIfNeeded() {
    guard !didStart else { return }
    didStart = true

    originalStdoutFD = dup(STDOUT_FILENO)
    originalStderrFD = dup(STDERR_FILENO)

    setvbuf(stdout, nil, _IONBF, 0)
    setvbuf(stderr, nil, _IONBF, 0)

    dup2(outputPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
    dup2(outputPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

    outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else { return }
      self?.consume(data)
      self?.forwardToOriginalOutputs(data)
    }
  }

  func clear() {
    DispatchQueue.main.async {
      self.entries.removeAll()
    }
  }

  private func forwardToOriginalOutputs(_ data: Data) {
    guard !data.isEmpty else { return }
    data.withUnsafeBytes { buffer in
      guard let baseAddress = buffer.baseAddress else { return }
      let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
      if originalStdoutFD >= 0 {
        _ = Darwin.write(originalStdoutFD, ptr, buffer.count)
      }
      if originalStderrFD >= 0 {
        _ = Darwin.write(originalStderrFD, ptr, buffer.count)
      }
    }
  }

  private func consume(_ data: Data) {
    sourceBuffer.append(data)

    while let newlineRange = sourceBuffer.firstRange(of: Data([0x0A])) {
      let lineData = sourceBuffer[..<newlineRange.lowerBound]
      sourceBuffer.removeSubrange(...newlineRange.lowerBound)

      guard let line = String(data: lineData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !line.isEmpty
      else { continue }

      DispatchQueue.main.async {
        self.entries.insert(
          Entry(
            timestamp: Date(),
            stream: self.inferStream(from: line),
            message: line
          ),
          at: 0
        )
        if self.entries.count > self.maxEntries {
          self.entries.removeLast(self.entries.count - self.maxEntries)
        }
      }
    }
  }

  private func inferStream(from line: String) -> String {
    let lowered = line.lowercased()
    if lowered.contains("error") || lowered.contains("failed") || lowered.contains("err=") {
      return "stderr"
    }
    return "stdout"
  }
}
