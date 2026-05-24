import Foundation
import GRDB

extension StorageManager {
  // MARK: - App Usage

  /// Per-app aggregation for a single day. Sessions are derived from
  /// consecutive screenshots sharing `frontmost_bundle_id`; cards are linked
  /// to apps by time-range overlap (AppSites holds domains, not bundle IDs).
  func fetchAppUsage(forDay day: String) -> [AppUsageEntry] {
    guard let dayDate = dateFormatter.date(from: day) else { return [] }
    let (startTs, endTs) = dayBoundaryTimestamps(for: dayDate)
    let cardBounds = fetchCardTimeBounds(forDay: day)
    return aggregateAppUsage(
      label: "day(\(day))",
      startTs: startTs,
      endTs: endTs,
      cardBounds: cardBounds
    )
  }

  /// Per-app aggregation across the week containing `date`. Reuses the same
  /// session-grouping logic over a 7-day window; cross-day gaps > 5min still
  /// split sessions, so longestSession remains well-defined.
  func fetchAppUsage(forWeekContaining date: Date) -> [AppUsageEntry] {
    let weekRange = TimelineWeekRange.containing(date)
    let startTs = Int(weekRange.weekStart.timeIntervalSince1970)
    let endTs = Int(weekRange.weekEnd.timeIntervalSince1970)
    let cardBounds = weekRange.days.flatMap { fetchCardTimeBounds(forDay: $0.dayString) }
    let label = "week(\(weekRange.days.first?.dayString ?? "?"))"
    return aggregateAppUsage(
      label: label,
      startTs: startTs,
      endTs: endTs,
      cardBounds: cardBounds
    )
  }

  /// Per-app session list for the inspector panel.
  func fetchAppSessions(bundleId: String, forDay day: String) -> [AppSession] {
    guard let dayDate = dateFormatter.date(from: day) else { return [] }
    let (startTs, endTs) = dayBoundaryTimestamps(for: dayDate)
    let normalizedTarget = bundleId.lowercased()

    let rows: [(bundleId: String, appName: String, capturedAt: Int)] =
      (try? timedRead("fetchAppSessions(\(bundleId)/\(day))") { db in
        try Row.fetchAll(
          db,
          sql: """
                SELECT frontmost_bundle_id, frontmost_app_name, captured_at
                FROM screenshots
                WHERE captured_at >= ?
                  AND captured_at < ?
                  AND is_deleted = 0
                  AND frontmost_bundle_id = ?
                  AND idle_seconds_at_capture < 60
                ORDER BY captured_at ASC
            """, arguments: [startTs, endTs, bundleId]
        )
        .compactMap { row -> (String, String, Int)? in
          guard let bid: String = row["frontmost_bundle_id"] else { return nil }
          let name: String = row["frontmost_app_name"] ?? bid
          let ts: Int = row["captured_at"]
          return (bid, name, ts)
        }
      }) ?? []

    // Mirror aggregateAppUsage's retroactive privacy filter.
    let blocked = Set(
      RecordingPrivacyPreferences.blockedApplicationIdentifiers().map { $0.lowercased() }
    )
    if blocked.contains(normalizedTarget) { return [] }

    return groupSessionsByApp(rows: rows)[bundleId]?.map { $0.session } ?? []
  }

  // MARK: - Internals

  // Shared aggregator for both Day and Week modes.
  private func aggregateAppUsage(
    label: String,
    startTs: Int,
    endTs: Int,
    cardBounds: [(id: Int64, startTs: Int, endTs: Int)]
  ) -> [AppUsageEntry] {
    typealias Row4 = (bundleId: String, appName: String, windowTitle: String?, capturedAt: Int)
    let rows: [Row4] =
      (try? timedRead("fetchAppUsage(\(label))") { db in
        try Row.fetchAll(
          db,
          sql: """
                SELECT frontmost_bundle_id, frontmost_app_name, frontmost_window_title, captured_at
                FROM screenshots
                WHERE captured_at >= ?
                  AND captured_at < ?
                  AND is_deleted = 0
                  AND frontmost_bundle_id IS NOT NULL
                  AND idle_seconds_at_capture < 60
                ORDER BY captured_at ASC
            """, arguments: [startTs, endTs]
        )
        .compactMap { row -> Row4? in
          guard let bundleId: String = row["frontmost_bundle_id"] else { return nil }
          let appName: String = row["frontmost_app_name"] ?? bundleId
          let title: String? = row["frontmost_window_title"]
          let capturedAt: Int = row["captured_at"]
          return (bundleId, appName, title, capturedAt)
        }
      }) ?? []

    // Defense-in-depth: drop rows whose bundleId matches the *current* blocked
    // list. Catches the case where a user blocks an app after history exists.
    let blocked = Set(
      RecordingPrivacyPreferences.blockedApplicationIdentifiers().map { $0.lowercased() }
    )
    let filtered: [Row4] =
      blocked.isEmpty
      ? rows
      : rows.filter { row in
        !blocked.contains(row.bundleId.lowercased())
          && !blocked.contains(row.appName.lowercased())
      }

    // Title occurrences per bundle, for "Top contexts" — counted before
    // session grouping so frequency reflects actual screenshot share.
    var titleCounts: [String: [String: Int]] = [:]
    for row in filtered {
      guard let title = row.windowTitle, !title.isEmpty else { continue }
      titleCounts[row.bundleId, default: [:]][title, default: 0] += 1
    }

    let sessionsByApp = groupSessionsByApp(
      rows: filtered.map { ($0.bundleId, $0.appName, $0.capturedAt) }
    )
    guard !sessionsByApp.isEmpty else { return [] }

    let secondsPerOccurrence = max(1, Int(ScreenshotConfig.interval.rounded()))

    var entries: [AppUsageEntry] = []
    entries.reserveCapacity(sessionsByApp.count)
    for (bundleId, sessions) in sessionsByApp {
      let appName = sessions.first?.appName ?? bundleId
      let total = sessions.reduce(0) { $0 + $1.session.durationSeconds }
      let longest = sessions.max(by: { $0.session.durationSeconds < $1.session.durationSeconds })

      var linked: Set<Int64> = []
      for entry in sessions {
        for bound in cardBounds {
          if entry.session.end.timeIntervalSince1970 > Double(bound.startTs)
            && entry.session.start.timeIntervalSince1970 < Double(bound.endTs)
          {
            linked.insert(bound.id)
          }
        }
      }

      let topContexts: [AppContextSummary] =
        (titleCounts[bundleId] ?? [:])
        .sorted { $0.value > $1.value }
        .prefix(5)
        .map {
          AppContextSummary(
            title: $0.key,
            occurrences: $0.value,
            seconds: $0.value * secondsPerOccurrence
          )
        }

      entries.append(
        AppUsageEntry(
          bundleId: bundleId,
          appName: appName,
          totalSeconds: total,
          sessionCount: sessions.count,
          longestSessionSeconds: longest?.session.durationSeconds ?? 0,
          longestSessionStart: longest?.session.start ?? Date(timeIntervalSince1970: 0),
          longestSessionEnd: longest?.session.end ?? Date(timeIntervalSince1970: 0),
          linkedCardIds: linked.sorted(),
          topContexts: topContexts
        ))
    }

    entries.sort { $0.totalSeconds > $1.totalSeconds }
    return entries
  }

  // Each screenshot contributes min(gap_to_next, 30). A new session starts when
  // bundleId changes OR gap > 300s. Last screenshot in a session contributes
  // one capture interval (~10s) to avoid undercounting a short final blip.
  private func groupSessionsByApp(
    rows: [(bundleId: String, appName: String, capturedAt: Int)]
  ) -> [String: [(appName: String, session: AppSession)]] {
    let perScreenshotCap = 30
    let sessionGapThreshold = 300
    let trailingContribution = max(1, Int(ScreenshotConfig.interval.rounded()))

    var result: [String: [(appName: String, session: AppSession)]] = [:]
    var currentBundle: String? = nil
    var currentAppName: String = ""
    var currentStartTs: Int = 0
    var currentLastTs: Int = 0
    var currentSeconds: Int = 0

    func flush() {
      guard let bundle = currentBundle else { return }
      let total = currentSeconds + trailingContribution
      let session = AppSession(
        start: Date(timeIntervalSince1970: TimeInterval(currentStartTs)),
        end: Date(timeIntervalSince1970: TimeInterval(currentLastTs + trailingContribution)),
        durationSeconds: total
      )
      result[bundle, default: []].append((appName: currentAppName, session: session))
    }

    for (i, row) in rows.enumerated() {
      let gapFromPrev = i == 0 ? Int.max : row.capturedAt - currentLastTs

      if currentBundle == nil
        || currentBundle != row.bundleId
        || gapFromPrev > sessionGapThreshold
      {
        flush()
        currentBundle = row.bundleId
        currentAppName = row.appName
        currentStartTs = row.capturedAt
        currentLastTs = row.capturedAt
        currentSeconds = 0
        continue
      }

      currentSeconds += min(gapFromPrev, perScreenshotCap)
      currentLastTs = row.capturedAt
      // Prefer the most recent non-empty app name for display.
      if !row.appName.isEmpty { currentAppName = row.appName }
    }
    flush()
    return result
  }

  // Light fetch used by overlap-matching. Full TimelineCard hydration happens
  // lazily via fetchTimelineCards(byIds:) when the inspector opens.
  private func fetchCardTimeBounds(
    forDay day: String
  ) -> [(id: Int64, startTs: Int, endTs: Int)] {
    (try? timedRead("fetchCardTimeBounds(\(day))") { db in
      try Row.fetchAll(
        db,
        sql: """
              SELECT id, start_ts, end_ts
              FROM timeline_cards
              WHERE day = ?
                AND is_deleted = 0
                AND start_ts IS NOT NULL
                AND end_ts IS NOT NULL
            """, arguments: [day]
      )
      .map { row in
        (id: row["id"] as Int64, startTs: row["start_ts"] as Int, endTs: row["end_ts"] as Int)
      }
    }) ?? []
  }

  // 4 AM local-time day boundary, consistent with TimelineReview/TimelineCards.
  private func dayBoundaryTimestamps(for dayDate: Date) -> (start: Int, end: Int) {
    let calendar = Calendar.current
    var startComponents = calendar.dateComponents([.year, .month, .day], from: dayDate)
    startComponents.hour = 4
    startComponents.minute = 0
    startComponents.second = 0
    let dayStart = calendar.date(from: startComponents) ?? dayDate
    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    return (Int(dayStart.timeIntervalSince1970), Int(dayEnd.timeIntervalSince1970))
  }
}
