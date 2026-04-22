import Foundation
import GRDB

extension StorageManager {

  func openAppActivitySegment(startTs: Int, bundleId: String?, appName: String?) -> Int64? {
    var newId: Int64?
    try? timedWrite("openAppActivitySegment") { db in
      try db.execute(
        sql: """
              INSERT INTO app_activity(start_ts, last_heartbeat_ts, bundle_id, app_name)
              VALUES (?, ?, ?, ?)
          """,
        arguments: [startTs, startTs, bundleId, appName])
      newId = db.lastInsertedRowID
    }
    return newId
  }

  func closeAppActivitySegment(id: Int64, endTs: Int) {
    try? timedWrite("closeAppActivitySegment") { db in
      try db.execute(
        sql: "UPDATE app_activity SET end_ts = ?, last_heartbeat_ts = ? WHERE id = ? AND end_ts IS NULL",
        arguments: [endTs, endTs, id]
      )
    }
  }

  func touchAppActivitySegment(id: Int64, nowTs: Int) {
    try? timedWrite("touchAppActivitySegment") { db in
      try db.execute(
        sql: "UPDATE app_activity SET last_heartbeat_ts = ? WHERE id = ? AND end_ts IS NULL",
        arguments: [nowTs, id]
      )
    }
  }

  func closeOrphanAppActivitySegments(capSeconds: Int) {
    try? timedWrite("closeOrphanAppActivitySegments") { db in
      try db.execute(
        sql: """
              UPDATE app_activity
              SET end_ts = COALESCE(last_heartbeat_ts, start_ts + ?)
              WHERE end_ts IS NULL
          """,
        arguments: [capSeconds]
      )
    }
  }

  func fetchAppActivitySegments(startTs: Int, endTs: Int) -> [AppActivitySegment] {
    let nowTs = Int(Date().timeIntervalSince1970)
    return
      (try? timedRead("fetchAppActivitySegments") { db in
        try Row.fetchAll(
          db,
          sql: """
                SELECT id,
                       start_ts,
                       COALESCE(end_ts, last_heartbeat_ts, ?) AS end_ts,
                       bundle_id, app_name
                FROM app_activity
                WHERE start_ts < ?
                  AND (end_ts IS NULL OR end_ts > ?)
                ORDER BY start_ts ASC
            """,
          arguments: [nowTs, endTs, startTs]
        ).map { row in
          AppActivitySegment(
            id: row["id"] ?? 0,
            startTs: row["start_ts"] ?? 0,
            endTs: row["end_ts"] ?? 0,
            bundleId: row["bundle_id"],
            appName: (row["app_name"] as? String) ?? "Unknown"
          )
        }
      }) ?? []
  }

  func appUsageForDay(_ date: Date) -> [AppUsageSample] {
    let cal = Calendar.current
    let start = cal.startOfDay(for: date)
    let end = cal.date(byAdding: .hour, value: 28, to: start) ?? date
    let startTs = Int(start.timeIntervalSince1970)
    let endTs = Int(end.timeIntervalSince1970)
    let nowTs = Int(Date().timeIntervalSince1970)

    let activitySegments =
      (try? timedRead("appUsageForDay.activity") { db in
        try Row.fetchAll(
          db,
          sql: """
                SELECT start_ts,
                       COALESCE(end_ts, last_heartbeat_ts, ?) AS end_ts,
                       bundle_id, app_name
                FROM app_activity
                WHERE start_ts < ?
                  AND (end_ts IS NULL OR end_ts > ?)
            """,
          arguments: [nowTs, endTs, startTs]
        )
      }) ?? []

    var activityByBundle: [String: (name: String, seconds: Double)] = [:]
    for row in activitySegments {
      let segStart: Int = row["start_ts"] ?? 0
      let segEnd: Int = row["end_ts"] ?? segStart
      let clampedStart = max(segStart, startTs)
      let clampedEnd = min(segEnd, endTs)
      let secs = Double(clampedEnd - clampedStart)
      guard secs > 0 else { continue }

      let appName: String = row["app_name"] ?? "Unknown"
      let bundleRaw: String? = row["bundle_id"]
      let bundle = bundleRaw ?? appName
      activityByBundle[bundle, default: (appName, 0)].seconds += secs
    }

    let shots =
      (try? timedRead("appUsageForDay.screenshots") { db in
        try Row.fetchAll(
          db,
          sql: """
                SELECT captured_at, active_app_name, active_app_bundle, active_url
                FROM screenshots
                WHERE captured_at >= ? AND captured_at <= ?
                  AND is_deleted = 0
                  AND active_app_name IS NOT NULL
                ORDER BY captured_at ASC
            """,
          arguments: [startTs, endTs]
        )
      }) ?? []

    let maxGap: Double = 3 * 60
    var durationByBundle: [String: (name: String, seconds: Double)] = [:]
    var urlDurationByBundle: [String: [String: Double]] = [:]

    for i in 0..<shots.count {
      let row = shots[i]
      guard let appName = row["active_app_name"] as? String else { continue }
      let bundle = row["active_app_bundle"] as? String ?? appName
      let ts = row["captured_at"] as? Int ?? 0

      let interval: Double
      if i + 1 < shots.count {
        let nextTs = shots[i + 1]["captured_at"] as? Int ?? ts
        interval = min(Double(nextTs - ts), maxGap)
      } else {
        interval = 30
      }
      guard interval > 0 else { continue }
      durationByBundle[bundle, default: (appName, 0)].seconds += interval

      if let urlString = row["active_url"] as? String,
        let domain = BrowserURLReader.domain(from: urlString)
      {
        urlDurationByBundle[bundle, default: [:]][domain, default: 0] += interval
      }
    }

    var mergedByBundle: [String: (name: String, seconds: Double)] = activityByBundle
    for (bundle, value) in durationByBundle where mergedByBundle[bundle] == nil {
      mergedByBundle[bundle] = value
    }

    let result = mergedByBundle.map { key, value in
      let topSites =
        (urlDurationByBundle[key] ?? [:])
        .map { (domain: $0.key, duration: $0.value) }
        .sorted { $0.duration > $1.duration }
        .prefix(5)
        .map { $0 }
      return AppUsageSample(
        appName: value.name,
        bundleIdentifier: key == value.name ? nil : key,
        duration: value.seconds,
        topSites: topSites
      )
    }

    return result.sorted { $0.duration > $1.duration }
  }
}
