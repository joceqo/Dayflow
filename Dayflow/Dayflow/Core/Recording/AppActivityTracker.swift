import AppKit
import CoreGraphics
import Foundation

/// Continuously tracks which app is frontmost and records each segment to `app_activity`.
/// Subscribes to NSWorkspace activation notifications so every app switch is captured with
/// precise timestamps (comparable to Rize/Timing), independent of screenshot cadence.
@MainActor
final class AppActivityTracker {
  static let shared = AppActivityTracker()

  private var activationObserver: NSObjectProtocol?
  private var sleepObserver: NSObjectProtocol?
  private var wakeObserver: NSObjectProtocol?
  private var ignoredAppsObserver: NSObjectProtocol?
  private var idleTimer: Timer?
  private var heartbeatTimer: Timer?

  private var currentSegmentId: Int64?
  private var currentBundleId: String?
  private var isStarted = false

  /// Close segments on idle beyond this threshold (seconds of no user input)
  private let idleThreshold: TimeInterval = 120
  /// Heartbeat interval — orphan segments will be accurate to within this window on crash
  private let heartbeatInterval: TimeInterval = 15
  /// Fallback cap if a segment somehow has no heartbeat (should never happen)
  private let orphanFallbackCapSeconds = 60

  private init() {}

  func start() {
    guard !isStarted else { return }
    isStarted = true

    // Close any orphan segments left behind by a crash / force-quit.
    // With heartbeats the cap is rarely used — orphans get capped at last heartbeat.
    StorageManager.shared.closeOrphanAppActivitySegments(capSeconds: orphanFallbackCapSeconds)

    // Seed with the current frontmost app
    if let app = NSWorkspace.shared.frontmostApplication {
      openSegment(bundleId: app.bundleIdentifier, appName: app.localizedName)
    }

    activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] note in
      MainActor.assumeIsolated {
        guard let self else { return }
        guard
          let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        self.switchTo(bundleId: app.bundleIdentifier, appName: app.localizedName)
      }
    }

    sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.screensDidSleepNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.closeCurrentSegment() }
    }

    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.screensDidWakeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        if let app = NSWorkspace.shared.frontmostApplication {
          self.openSegment(bundleId: app.bundleIdentifier, appName: app.localizedName)
        }
      }
    }

    // If the user adds an app to the ignore list while it's active, close it immediately
    ignoredAppsObserver = NotificationCenter.default.addObserver(
      forName: IgnoredAppsPreferences.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, let bid = self.currentBundleId else { return }
        if IgnoredAppsPreferences.contains(bundleId: bid) {
          self.closeCurrentSegment()
        }
      }
    }

    // Idle check every 30s — close segment if user has been idle > threshold
    idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.pollIdle() }
    }

    // Heartbeat timer — keep last_heartbeat_ts fresh so a crash loses at most one interval
    heartbeatTimer = Timer.scheduledTimer(
      withTimeInterval: heartbeatInterval, repeats: true
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.heartbeat() }
    }
  }

  func stop() {
    closeCurrentSegment()

    if let o = activationObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(o)
      activationObserver = nil
    }
    if let o = sleepObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(o)
      sleepObserver = nil
    }
    if let o = wakeObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(o)
      wakeObserver = nil
    }
    if let o = ignoredAppsObserver {
      NotificationCenter.default.removeObserver(o)
      ignoredAppsObserver = nil
    }
    idleTimer?.invalidate()
    idleTimer = nil
    heartbeatTimer?.invalidate()
    heartbeatTimer = nil
    isStarted = false
  }

  private func heartbeat() {
    guard let id = currentSegmentId else { return }
    let now = Int(Date().timeIntervalSince1970)
    StorageManager.shared.touchAppActivitySegment(id: id, nowTs: now)
  }

  private func switchTo(bundleId: String?, appName: String?) {
    // Skip no-op switches to the same bundle
    guard bundleId != currentBundleId else { return }
    closeCurrentSegment()

    if let bid = bundleId, IgnoredAppsPreferences.contains(bundleId: bid) {
      return
    }
    openSegment(bundleId: bundleId, appName: appName)
  }

  private func openSegment(bundleId: String?, appName: String?) {
    if let bid = bundleId, IgnoredAppsPreferences.contains(bundleId: bid) { return }
    let now = Int(Date().timeIntervalSince1970)
    currentSegmentId = StorageManager.shared.openAppActivitySegment(
      startTs: now, bundleId: bundleId, appName: appName)
    currentBundleId = bundleId
  }

  private func closeCurrentSegment() {
    guard let id = currentSegmentId else { return }
    let now = Int(Date().timeIntervalSince1970)
    StorageManager.shared.closeAppActivitySegment(id: id, endTs: now)
    currentSegmentId = nil
    currentBundleId = nil
  }

  private func pollIdle() {
    let idleSecs = idleSecondsSinceLastInput()
    if idleSecs > idleThreshold {
      if currentSegmentId != nil { closeCurrentSegment() }
    } else {
      // Active — make sure a segment is open for the frontmost app
      if currentSegmentId == nil, let app = NSWorkspace.shared.frontmostApplication {
        openSegment(bundleId: app.bundleIdentifier, appName: app.localizedName)
      }
    }
  }

  private func idleSecondsSinceLastInput() -> TimeInterval {
    let anyEvent = CGEventType(rawValue: UInt32.max)!
    let secs = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyEvent)
    return secs.isFinite && secs >= 0 ? secs : 0
  }
}
