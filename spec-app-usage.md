# Spec: App Usage View

**Goal:** Add a per-app time-tracking tab to Dayflow (RescueTime/Timing style). App durations are derived from the existing screenshot stream — no new OS APIs needed beyond reading `NSWorkspace.shared.frontmostApplication` at capture time. AI cards link back to apps, but app durations are instant (no AI needed).

---

## 1. Database migration

Add two columns to `screenshots` and one new table.

### 1a. New columns on `screenshots`

```sql
ALTER TABLE screenshots ADD COLUMN frontmost_bundle_id TEXT;
ALTER TABLE screenshots ADD COLUMN frontmost_app_name TEXT;
```

- `frontmost_bundle_id` — e.g. `"com.todesktop.230313mzl4w4u92"` (Cursor), `nil` for Finder/unknown
- `frontmost_app_name` — e.g. `"Cursor"`, display name from `RunningApplication.localizedName`
- Both nullable — historical screenshots before this migration have `NULL`; they are simply excluded from app-time queries

Migration identifier: `"screenshots_frontmost_app"` — appended to the existing migration sequence in `StorageManager.migrate()`.

### 1b. No additional table needed

App sessions are computed on-the-fly by grouping consecutive screenshots sharing the same `frontmost_bundle_id`. This avoids a separate sessions table that would need incremental maintenance and drift correction.

---

## 2. Capture change — `ScreenRecorder.swift`

In `captureScreenshot()`, just before calling `StorageManager.shared.saveScreenshot(...)`, read the frontmost app:

```swift
let frontmostApp = NSWorkspace.shared.frontmostApplication
let bundleId = frontmostApp?.bundleIdentifier
let appName = frontmostApp?.localizedName
```

Pass both to a new overload of `saveScreenshot`:

```swift
StorageManager.shared.saveScreenshot(
    url: url,
    capturedAt: capturedAt,
    idleSecondsAtCapture: idleSeconds,
    frontmostBundleId: bundleId,
    frontmostAppName: appName
)
```

**Note:** The existing privacy check (`IgnoredAppsPreferences.contains(bundleId:)`) already runs before the capture. If a screenshot is skipped, no row is written at all — the app accumulates no time. This is the correct behavior.

**Note:** Screenshots taken while the machine is locked or screensaver is running already have `idleSecondsAtCapture` well above any threshold. No special case is needed.

---

## 3. Storage layer — `StorageManager+AppUsage.swift`

New extension file. Two public methods.

### 3a. `fetchAppUsage(forDay:) -> [AppUsageEntry]`

```swift
struct AppUsageEntry: Identifiable {
    let bundleId: String          // e.g. "com.apple.Safari"
    let appName: String           // e.g. "Safari"
    var totalSeconds: Int         // sum of screenshot intervals attributed to this app
    var sessionCount: Int         // number of contiguous runs (gap > 5 min = new session)
    var longestSessionSeconds: Int
    var longestSessionStart: Date
    var longestSessionEnd: Date
    var linkedCardIds: [Int64]    // timeline_cards.id where appSites.primary or secondary matches
}
```

**Query logic:**

```sql
SELECT frontmost_bundle_id, frontmost_app_name, captured_at
FROM screenshots
WHERE captured_at >= :dayStart
  AND captured_at < :dayEnd
  AND is_deleted = 0
  AND frontmost_bundle_id IS NOT NULL
  AND idle_seconds_at_capture < 60        -- exclude screenshots where user was idle
ORDER BY captured_at ASC
```

Day boundaries use the existing 4 AM convention (`dayBoundary(for:)` already exists in the codebase).

**Session grouping (in Swift after the query):**

Iterate rows sorted by `captured_at`. A new session starts when:
- `bundleId` changes, **or**
- gap between consecutive screenshots of the same app > 300 seconds (5 minutes)

Each screenshot contributes `min(gap_to_next, 30)` seconds to that app's total — capped at 30s to prevent a single gap from inflating totals (e.g. screenshots taken after a long idle). The last screenshot in a session contributes the capture interval (default 10s).

**Card linking:**

After grouping, run a second query for the day's timeline cards:

```sql
SELECT id, metadata FROM timeline_cards
WHERE day = :day AND is_deleted = 0
```

Decode `metadata` JSON → `appSites.primary` and `appSites.secondary`. If either matches a `bundleId` (case-insensitive bundle ID match, or app name substring match), add the card's `id` to `linkedCardIds`.

### 3b. `fetchAppSessions(bundleId:forDay:) -> [AppSession]`

Used by the inspector panel.

```swift
struct AppSession {
    let start: Date
    let end: Date
    var durationSeconds: Int
}
```

Same query as above filtered to one `bundleId`, returns the computed sessions array.

---

## 4. New SwiftUI views

### 4a. `AppUsageView.swift`

Top-level view rendered when the `.appUsage` sidebar tab is active. Mirrors `TimelineView` layout conventions.

```
AppUsageView
├── AppUsageHeaderView       (date nav + Day/Week toggle + pause pill — reuse header components)
├── TabFilterBar             (existing component, pass categories from shared state)
└── HStack
    ├── AppListView          (scrollable ranked list)
    └── AppInspectorView     (right panel, 264px wide)
```

**State:**
```swift
@State private var selectedBundleId: String? = nil
@State private var entries: [AppUsageEntry] = []
@State private var viewMode: AppUsageMode = .byApp  // .byApp | .byCategory
```

On appear and on date change: call `StorageManager.shared.fetchAppUsage(forDay:)` on a background task, publish results to `entries`.

### 4b. `AppListView.swift`

Renders:
- **Summary header:** total active seconds (formatted as "7h 42m"), subtitle "active today · N apps used"
- **Day timeline bar:** proportional colored segments per app (top 5 apps + grey "other"), 5px height
- **App rows:** ranked by `totalSeconds` descending, each row shows:
  - App icon (from `NSWorkspace.shared.icon(forFile:)` or `NSImage` from bundle, fallback to generic app icon) — 28×28, cornerRadius 7
  - App name (Figtree 13 semibold)
  - Duration label (Figtree 11 semibold, `#6B6560`)
  - Progress bar (fraction of longest app's time)
  - Percentage label (10.5px, `#C5BDB8`, orange when selected)
- **"N other apps" row** collapsed below a divider when more than 6 apps

Selecting a row sets `selectedBundleId` in the parent.

### 4c. `AppInspectorView.swift`

Right panel, 264px, `white@70%`, left border `#ECECEC`, `UnevenRoundedRectangle` with trailing corners r8.

Shows for the selected app:
- App icon (34×34, r9) + app name (InstrumentSerif fallback Georgia 15pt) + meta ("2h 14m · 29% of today")
- **Stats row:** two `StatBox` cards — "Sessions" (count + "avg Xm each") and "Longest" (duration + time range)
- **Section header** "Activity cards" (9.5px caps)
- **Mini-cards** for each `linkedCardId` — fetched by `StorageManager.shared.fetchTimelineCards(byIds:)` (new thin helper). Each mini-card shows time-tag, title, category badge. Pending cards (no title) show blinking dot + "Analyzing…"
- **Notice box** at bottom: "⚡ App times are instant — no AI needed. Cards appear as analysis finishes."

When no app is selected: empty state with "Select an app to see details" in muted text.

---

## 5. Sidebar changes

### 5a. `SidebarView.swift` — add case

```swift
enum SidebarIcon: CaseIterable {
  case timeline
  case daily
  case appUsage   // ← new, position 3 (after daily)
  case weekly
  case chat
  case journal
  case bug
  case settings
}
```

Asset name: `nil` (no PNG in asset catalog — use SF Symbol `"chart.bar.fill"` as the system fallback, or ship a custom SVG via a new `AppUsageIcon.imageset`).

Display name: `"Apps"`
Analytics tab name: `"app_usage"`

Update `visibleIcons` filter to keep the new case visible.

### 5b. `Layout.swift` — add switch case

```swift
case .appUsage:
  AppUsageView(selectedDate: $selectedDate)
```

Add to `handleTabSelectionChange`: no badge logic needed.

---

## 6. App icon resolution

`NSWorkspace.shared.icon(forFile:)` requires a file path, not a bundle ID. Resolution order:

1. `NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)` → get bundle URL
2. `NSWorkspace.shared.icon(forFile: bundleURL.path)` → `NSImage`
3. Resize to 28×28 for list rows, 34×34 for inspector

Cache in a `[String: NSImage]` dictionary keyed by bundle ID. This runs on the main thread (AppKit requirement) but results are small enough to cache for the day.

---

## 7. Aggregation correctness constraints

- **Idle exclusion threshold:** `idle_seconds_at_capture < 60`. Screenshots where the user was idle for ≥ 60 seconds are excluded from all time totals. This matches the natural expectation that a locked screen or away-from-keyboard spell doesn't count.
- **Screenshot interval cap:** Each screenshot's contribution is capped at `min(nextCapturedAt - capturedAt, 30)`. Handles edge cases: app crash, long sleep, first screenshot of day.
- **NULL bundle IDs:** Excluded from aggregation. Historical screenshots and system UI screenshots (e.g., screensaver) fall into this bucket.
- **Privacy:** Bundle IDs for apps in `IgnoredAppsPreferences` are never written to the DB (the screenshot is skipped entirely). No retroactive filtering is needed.
- **Day boundary:** 4 AM local time, consistent with the rest of the app.

---

## 8. Files to create / modify

| File | Action |
|------|--------|
| `Core/Storage/StorageManager.swift` | Add migration `"screenshots_frontmost_app"`, update `saveScreenshot` signature |
| `Core/Storage/StorageManager+AppUsage.swift` | **New** — `fetchAppUsage`, `fetchAppSessions`, `fetchTimelineCards(byIds:)` |
| `Core/Recording/ScreenRecorder.swift` | Read frontmost app before `saveScreenshot` call |
| `Core/Storage/StorageModels.swift` | Add `frontmostBundleId`, `frontmostAppName` to `Screenshot` struct; add `AppUsageEntry`, `AppSession` |
| `Views/UI/AppUsage/AppUsageView.swift` | **New** |
| `Views/UI/AppUsage/AppListView.swift` | **New** |
| `Views/UI/AppUsage/AppInspectorView.swift` | **New** |
| `Views/UI/MainView/SidebarView.swift` | Add `.appUsage` case |
| `Views/UI/MainView/Layout.swift` | Add `.appUsage` switch case |

---

## 9. Out of scope

- Week view (aggregate across multiple days) — defer to v2
- Export / share — defer
- Category override per app — defer
- Notifications / goals ("You've spent 3h in Safari") — defer
- Retroactive backfill of old screenshots — not feasible without frontmost app data; those rows stay NULL
