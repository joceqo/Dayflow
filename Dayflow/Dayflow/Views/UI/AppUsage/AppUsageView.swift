import AppKit
import SwiftUI

struct AppUsageView: View {
  @Binding var selectedDate: Date

  @State private var entries: [AppUsageEntry] = []
  @State private var selectedBundleId: String? = nil
  @State private var isLoading: Bool = false
  @State private var loadToken: Int = 0
  @State private var loadedDayString: String? = nil

  // Roughly 1.5× the default screenshot interval — close enough to "live" for
  // a recording cadence of ~10s without thrashing the DB. Reloads silently
  // when entries already exist (no loader flash).
  private let refreshInterval: TimeInterval = 15
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
          isLoading: isLoading
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        Rectangle()
          .fill(Color(hex: "ECECEC"))
          .frame(width: 1)
          .frame(maxHeight: .infinity)

        AppInspectorView(
          entry: selectedEntry,
          totalDaySeconds: totalDaySeconds
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
    .onReceive(refreshTimer) { _ in load(force: true) }
  }

  private var header: some View {
    let dayInfo = selectedDate.getDayInfoFor4AMBoundary()
    let formatter: DateFormatter = {
      let f = DateFormatter()
      f.dateFormat = "EEEE, MMMM d"
      return f
    }()

    return HStack(alignment: .firstTextBaseline) {
      Text("Apps")
        .font(.custom("InstrumentSerif-Regular", size: 26))
        .foregroundColor(.black)
      Spacer(minLength: 12)
      Text(formatter.string(from: dayInfo.startOfDay))
        .font(.custom("Figtree", size: 12).weight(.medium))
        .foregroundColor(Color(hex: "796E64"))
    }
  }

  private var selectedEntry: AppUsageEntry? {
    guard let id = selectedBundleId else { return nil }
    return entries.first(where: { $0.bundleId == id })
  }

  private var totalDaySeconds: Int {
    entries.reduce(0) { $0 + $1.totalSeconds }
  }

  private func load(force: Bool) {
    let dayString = selectedDate.getDayInfoFor4AMBoundary().dayString
    if !force, loadedDayString == dayString { return }

    loadToken &+= 1
    let token = loadToken
    // Only show the loader when we have nothing on screen yet — silent
    // refreshes mustn't flash the empty state.
    isLoading = entries.isEmpty

    Task.detached(priority: .userInitiated) {
      let fetched = StorageManager.shared.fetchAppUsage(forDay: dayString)
      await MainActor.run {
        guard token == self.loadToken else { return }
        self.entries = fetched
        self.loadedDayString = dayString
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
