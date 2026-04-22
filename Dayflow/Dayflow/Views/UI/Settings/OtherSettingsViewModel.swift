import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class OtherSettingsViewModel: ObservableObject {
  @Published var analyticsEnabled: Bool {
    didSet {
      guard analyticsEnabled != oldValue else { return }
      AnalyticsService.shared.setOptIn(analyticsEnabled)
    }
  }
  @Published var showDockIcon: Bool {
    didSet {
      guard showDockIcon != oldValue else { return }
      UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon")
      NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }
  }
  @Published var showTimelineAppIcons: Bool {
    didSet {
      guard showTimelineAppIcons != oldValue else { return }
      UserDefaults.standard.set(showTimelineAppIcons, forKey: "showTimelineAppIcons")
    }
  }
  @Published var saveAllTimelapsesToDisk: Bool {
    didSet {
      guard saveAllTimelapsesToDisk != oldValue else { return }
      TimelapsePreferences.saveAllTimelapsesToDisk = saveAllTimelapsesToDisk
    }
  }
  @Published var outputLanguageOverride: String
  @Published var isOutputLanguageOverrideSaved: Bool = true

  @Published var exportStartDate: Date
  @Published var exportEndDate: Date
  @Published var isExportingTimelineRange = false
  @Published var exportStatusMessage: String?
  @Published var exportErrorMessage: String?
  @Published var reprocessDayDate: Date
  @Published var isReprocessingDay = false
  @Published var reprocessStatusMessage: String?
  @Published var reprocessErrorMessage: String?
  @Published var showReprocessDayConfirm = false

  @Published var ignoredApps: [IgnoredApp] = []
  @Published var ignoredAppErrorMessage: String?
  private var ignoredAppsObserver: NSObjectProtocol?

  init() {
    analyticsEnabled = AnalyticsService.shared.isOptedIn
    showDockIcon = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
    showTimelineAppIcons =
      UserDefaults.standard.object(forKey: "showTimelineAppIcons") as? Bool ?? true
    saveAllTimelapsesToDisk = TimelapsePreferences.saveAllTimelapsesToDisk
    outputLanguageOverride = LLMOutputLanguagePreferences.override
    exportStartDate = timelineDisplayDate(from: Date())
    exportEndDate = timelineDisplayDate(from: Date())
    reprocessDayDate = timelineDisplayDate(from: Date())
    ignoredApps = IgnoredAppsPreferences.apps

    ignoredAppsObserver = NotificationCenter.default.addObserver(
      forName: IgnoredAppsPreferences.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.ignoredApps = IgnoredAppsPreferences.apps
    }
  }

  deinit {
    if let observer = ignoredAppsObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  func presentAddIgnoredAppPanel() {
    ignoredAppErrorMessage = nil

    let panel = NSOpenPanel()
    panel.title = "Select an app to ignore"
    panel.prompt = "Ignore"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.treatsFilePackagesAsDirectories = false
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    if #available(macOS 11.0, *) {
      panel.allowedContentTypes = [UTType.application]
    } else {
      panel.allowedFileTypes = ["app"]
    }

    guard panel.runModal() == .OK else { return }

    var added = 0
    var skipped: [String] = []
    for url in panel.urls {
      guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else {
        skipped.append(url.lastPathComponent)
        continue
      }
      let displayName =
        (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
        ?? (bundle.infoDictionary?["CFBundleName"] as? String)
        ?? url.deletingPathExtension().lastPathComponent
      IgnoredAppsPreferences.add(IgnoredApp(bundleId: bundleId, name: displayName))
      added += 1
    }

    if added == 0 && !skipped.isEmpty {
      ignoredAppErrorMessage = "Couldn't read bundle info for: \(skipped.joined(separator: ", "))"
    } else if !skipped.isEmpty {
      ignoredAppErrorMessage = "Skipped (no bundle ID): \(skipped.joined(separator: ", "))"
    }
  }

  func removeIgnoredApp(bundleId: String) {
    IgnoredAppsPreferences.remove(bundleId: bundleId)
  }

  func markOutputLanguageOverrideEdited() {
    let trimmed = outputLanguageOverride.trimmingCharacters(in: .whitespacesAndNewlines)
    let savedValue = LLMOutputLanguagePreferences.override
    isOutputLanguageOverrideSaved = trimmed == savedValue
  }

  func saveOutputLanguageOverride() {
    let trimmed = outputLanguageOverride.trimmingCharacters(in: .whitespacesAndNewlines)
    outputLanguageOverride = trimmed
    LLMOutputLanguagePreferences.override = trimmed
    isOutputLanguageOverrideSaved = true
  }

  func resetOutputLanguageOverride() {
    outputLanguageOverride = ""
    LLMOutputLanguagePreferences.override = ""
    isOutputLanguageOverrideSaved = true
  }

  func refreshAnalyticsState() {
    analyticsEnabled = AnalyticsService.shared.isOptedIn
  }

  func exportTimelineRange() {
    guard !isExportingTimelineRange else { return }

    let start = timelineDisplayDate(from: exportStartDate)
    let end = timelineDisplayDate(from: exportEndDate)

    guard start <= end else {
      exportErrorMessage = "Start date must be on or before end date."
      exportStatusMessage = nil
      return
    }

    isExportingTimelineRange = true
    exportStatusMessage = nil
    exportErrorMessage = nil

    Task.detached(priority: .userInitiated) { [start, end] in
      let calendar = Calendar.current
      let dayFormatter = DateFormatter()
      dayFormatter.dateFormat = "yyyy-MM-dd"

      var cursor = start
      let endDate = end

      var sections: [String] = []
      var totalActivities = 0
      var dayCount = 0

      while cursor <= endDate {
        let dayString = dayFormatter.string(from: cursor)
        let cards = StorageManager.shared.fetchTimelineCards(forDay: dayString)
        totalActivities += cards.count
        let section = TimelineClipboardFormatter.makeMarkdown(for: cursor, cards: cards)
        sections.append(section)
        dayCount += 1

        guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
        cursor = next
      }

      let divider = "\n\n---\n\n"
      let exportText = sections.joined(separator: divider)

      await MainActor.run {
        self.presentSavePanelAndWrite(
          exportText: exportText,
          startDate: start,
          endDate: end,
          dayCount: dayCount,
          activityCount: totalActivities
        )
      }
    }
  }

  func reprocessSelectedDay() {
    guard !isReprocessingDay else { return }

    let normalizedDate = timelineDisplayDate(from: reprocessDayDate)
    let dayString = DateFormatter.yyyyMMdd.string(from: normalizedDate)

    isReprocessingDay = true
    reprocessErrorMessage = nil
    reprocessStatusMessage = "Starting reprocess for \(dayString)…"

    AnalysisManager.shared.reprocessDay(
      dayString,
      progressHandler: { [weak self] message in
        Task { @MainActor in
          self?.reprocessStatusMessage = message
        }
      },
      completion: { [weak self] result in
        Task { @MainActor in
          guard let self else { return }
          switch result {
          case .success:
            if self.reprocessStatusMessage == nil {
              self.reprocessStatusMessage = "Reprocess completed."
            }
          case .failure(let error):
            self.reprocessErrorMessage = error.localizedDescription
          }
          self.isReprocessingDay = false
        }
      })
  }

  @MainActor
  private func presentSavePanelAndWrite(
    exportText: String,
    startDate: Date,
    endDate: Date,
    dayCount: Int,
    activityCount: Int
  ) {
    let dayFormatter = DateFormatter()
    dayFormatter.dateFormat = "yyyy-MM-dd"

    let savePanel = NSSavePanel()
    savePanel.title = "Export timeline"
    savePanel.prompt = "Export"
    savePanel.nameFieldStringValue =
      "Dayflow timeline \(dayFormatter.string(from: startDate)) to \(dayFormatter.string(from: endDate)).md"
    savePanel.allowedContentTypes = [.text, .plainText]
    savePanel.canCreateDirectories = true

    let response = savePanel.runModal()

    defer { isExportingTimelineRange = false }

    guard response == .OK, let url = savePanel.url else {
      exportStatusMessage = nil
      exportErrorMessage = "Export canceled"
      return
    }

    do {
      try exportText.write(to: url, atomically: true, encoding: .utf8)
      exportErrorMessage = nil
      exportStatusMessage =
        "Saved \(activityCount) activit\(activityCount == 1 ? "y" : "ies") across \(dayCount) day\(dayCount == 1 ? "" : "s") to \(url.lastPathComponent)"

      AnalyticsService.shared.capture(
        "timeline_exported",
        [
          "start_day": dayFormatter.string(from: startDate),
          "end_day": dayFormatter.string(from: endDate),
          "day_count": dayCount,
          "activity_count": activityCount,
          "format": "markdown",
          "file_extension": url.pathExtension.lowercased(),
        ])
    } catch {
      exportStatusMessage = nil
      exportErrorMessage = "Couldn't save file: \(error.localizedDescription)"
    }
  }
}
