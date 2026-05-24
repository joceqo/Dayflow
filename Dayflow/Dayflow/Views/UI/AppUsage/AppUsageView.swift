import AppKit
import SwiftUI

struct AppUsageView: View {
  @Binding var selectedDate: Date

  @State private var mode: TimelineMode = .day
  @State private var entries: [AppUsageEntry] = []
  @State private var selectedBundleId: String? = nil
  @State private var isLoading: Bool = false
  @State private var loadToken: Int = 0
  @State private var loadedCacheKey: String? = nil
  @Namespace private var modeToggleNamespace

  // Roughly 1.5× the default screenshot interval — close enough to "live" for
  // a recording cadence of ~10s without thrashing the DB. Reloads silently
  // when entries already exist (no loader flash).
  private let refreshTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
        .padding(.top, 24)
        .padding(.horizontal, 24)

      HStack(alignment: .top, spacing: 0) {
        AppListView(
          entries: entries,
          selectedBundleId: $selectedBundleId,
          isLoading: isLoading,
          rangeLabel: rangeLabel
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        Rectangle()
          .fill(Color(hex: "ECECEC"))
          .frame(width: 1)
          .frame(maxHeight: .infinity)

        AppInspectorView(
          entry: selectedEntry,
          totalRangeSeconds: totalRangeSeconds,
          rangeLabel: rangeLabel
        )
        .frame(width: 264)
        .frame(maxHeight: .infinity)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color.clear)
    .onAppear { load(force: true) }
    .onChange(of: selectedDate) { _, _ in load(force: false) }
    .onChange(of: mode) { _, _ in load(force: false) }
    .onReceive(refreshTimer) { _ in load(force: true) }
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: 12) {
      navButton(systemName: "chevron.left", enabled: true, action: navigateBackward)
      Text(titleText)
        .font(.custom("InstrumentSerif-Regular", size: 22))
        .foregroundColor(.black)
        .lineLimit(1)
      navButton(
        systemName: "chevron.right",
        enabled: canNavigateForward,
        action: navigateForward
      )

      if !isOnToday {
        todayButton
          .transition(.opacity.combined(with: .scale(scale: 0.94)))
      }

      Spacer(minLength: 8)

      modeToggle
    }
    .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isOnToday)
  }

  private func navButton(
    systemName: String,
    enabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: { if enabled { action() } }) {
      ZStack {
        Circle()
          .fill(Color(hex: "FFEBD3").opacity(0.0))
          .frame(width: 28, height: 28)
        Image(systemName: systemName)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(
            enabled ? Color(hex: "796E64") : Color(hex: "C5BDB8")
          )
      }
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
  }

  private var todayButton: some View {
    Button(action: jumpToToday) {
      Text("Today")
        .font(.custom("Figtree", size: 12).weight(.medium))
        .foregroundColor(Color(hex: "796E64"))
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Color(hex: "FFEFE4"))
        .clipShape(Capsule(style: .continuous))
        .overlay(
          Capsule(style: .continuous)
            .stroke(Color(hex: "F2D2BD"), lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
  }

  private var modeToggle: some View {
    HStack(spacing: 0) {
      ForEach(TimelineMode.allCases) { m in
        let isSelected = mode == m
        Button(action: {
          guard mode != m else { return }
          withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            mode = m
          }
        }) {
          ZStack {
            if isSelected {
              Capsule(style: .continuous)
                .fill(
                  LinearGradient(
                    colors: [
                      Color(hex: "FFB18D").opacity(0.6),
                      Color(hex: "FFA46F"),
                      Color(hex: "FFB18D"),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                  )
                )
                .matchedGeometryEffect(
                  id: "app_usage_mode_highlight",
                  in: modeToggleNamespace
                )
            }
            Text(m.title)
              .font(.custom("Figtree", size: 12).weight(.medium))
              .foregroundColor(isSelected ? .white : Color(hex: "796E64"))
              .frame(width: 52, height: 26)
          }
        }
        .buttonStyle(.plain)
      }
    }
    .frame(width: 104, height: 26)
    .background(Color(hex: "FFEFE4"))
    .clipShape(Capsule(style: .continuous))
    .overlay(
      Capsule(style: .continuous)
        .stroke(Color(hex: "F2D2BD"), lineWidth: 1)
    )
  }

  // MARK: - Header data

  private var titleText: String {
    switch mode {
    case .day:
      let info = selectedDate.getDayInfoFor4AMBoundary()
      let f = DateFormatter()
      f.dateFormat = isOnToday ? "'Today, ' MMMM d" : "EEEE, MMMM d"
      return f.string(from: info.startOfDay)
    case .week:
      return TimelineWeekRange.containing(selectedDate).title
    }
  }

  private var isOnToday: Bool {
    switch mode {
    case .day:
      return timelineIsToday(selectedDate)
    case .week:
      return TimelineWeekRange.containing(selectedDate).containsToday
    }
  }

  private var canNavigateForward: Bool {
    switch mode {
    case .day:
      return !timelineIsToday(selectedDate)
    case .week:
      return TimelineWeekRange.containing(selectedDate).canNavigateForward
    }
  }

  private func navigateBackward() {
    let calendar = Calendar.current
    let step = mode == .week ? -7 : -1
    let target = calendar.date(byAdding: .day, value: step, to: selectedDate) ?? selectedDate
    selectedDate = normalizedTimelineDate(target)
  }

  private func navigateForward() {
    guard canNavigateForward else { return }
    let calendar = Calendar.current
    let step = mode == .week ? 7 : 1
    let target = calendar.date(byAdding: .day, value: step, to: selectedDate) ?? selectedDate
    selectedDate = normalizedTimelineDate(target)
  }

  private func jumpToToday() {
    selectedDate = timelineDisplayDate(from: Date())
  }

  // MARK: - Data load

  private var selectedEntry: AppUsageEntry? {
    guard let id = selectedBundleId else { return nil }
    return entries.first(where: { $0.bundleId == id })
  }

  private var totalRangeSeconds: Int {
    entries.reduce(0) { $0 + $1.totalSeconds }
  }

  private var rangeLabel: String {
    switch mode {
    case .day:
      return isOnToday ? "today" : "this day"
    case .week:
      return isOnToday ? "this week" : "the week"
    }
  }

  private var currentCacheKey: String {
    switch mode {
    case .day:
      return "day:\(selectedDate.getDayInfoFor4AMBoundary().dayString)"
    case .week:
      let range = TimelineWeekRange.containing(selectedDate)
      return "week:\(range.days.first?.dayString ?? "?")"
    }
  }

  private func load(force: Bool) {
    let cacheKey = currentCacheKey
    if !force, loadedCacheKey == cacheKey { return }

    loadToken &+= 1
    let token = loadToken
    // Only show the loader when we have nothing on screen yet — silent
    // refreshes mustn't flash the empty state.
    isLoading = entries.isEmpty

    let captureMode = mode
    let captureDate = selectedDate

    Task.detached(priority: .userInitiated) {
      let fetched: [AppUsageEntry]
      switch captureMode {
      case .day:
        let day = captureDate.getDayInfoFor4AMBoundary().dayString
        fetched = StorageManager.shared.fetchAppUsage(forDay: day)
      case .week:
        fetched = StorageManager.shared.fetchAppUsage(forWeekContaining: captureDate)
      }
      await MainActor.run {
        guard token == self.loadToken else { return }
        self.entries = fetched
        self.loadedCacheKey = cacheKey
        self.isLoading = false
        if let current = self.selectedBundleId,
          !fetched.contains(where: { $0.bundleId == current })
        {
          self.selectedBundleId = nil
        }
        if self.selectedBundleId == nil {
          self.selectedBundleId = fetched.first?.bundleId
        }
      }
    }
  }
}

// MARK: - App icon cache

@MainActor
final class AppIconCache {
  static let shared = AppIconCache()
  private var cache: [String: NSImage] = [:]

  func icon(forBundleId bundleId: String) -> NSImage? {
    if let cached = cache[bundleId] { return cached }
    guard
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
    else {
      return nil
    }
    let image = NSWorkspace.shared.icon(forFile: url.path)
    cache[bundleId] = image
    return image
  }
}

struct AppUsageView_Previews: PreviewProvider {
  static var previews: some View {
    AppUsageView(selectedDate: .constant(Date()))
      .frame(width: 1100, height: 760)
  }
}
