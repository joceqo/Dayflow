import AppKit
import SwiftUI

struct AppListView: View {
  let entries: [AppUsageEntry]
  @Binding var selectedBundleId: String?
  let isLoading: Bool
  // "today" or "this week" — used in the "active … · N apps used" subtitle so
  // the unit matches the parent's mode.
  let rangeLabel: String

  private let visibleRowCutoff = 6
  // Stable palette for the day-timeline bar. Greys reserved for "other".
  private let segmentPalette: [Color] = [
    Color(hex: "F96E00"),
    Color(hex: "FFA777"),
    Color(hex: "EAB47D"),
    Color(hex: "8FB7C9"),
    Color(hex: "B6A0CC"),
  ]
  private let otherColor = Color(hex: "C5BDB8")

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        summaryHeader
          .padding(.horizontal, 24)
          .padding(.top, 12)

        if !entries.isEmpty {
          timelineBar
            .padding(.horizontal, 24)
        }

        if entries.isEmpty {
          emptyState
            .frame(maxWidth: .infinity, minHeight: 200)
            .padding(.horizontal, 24)
        } else {
          appRows
            .padding(.horizontal, 24)
        }

        Spacer(minLength: 24)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var summaryHeader: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(totalLabel)
        .font(.custom("InstrumentSerif-Regular", size: 28))
        .foregroundColor(.black)
      Text(subtitleLabel)
        .font(.custom("Figtree", size: 11).weight(.medium))
        .foregroundColor(Color(hex: "6B6560"))
    }
  }

  private var timelineBar: some View {
    GeometryReader { geo in
      let totalWidth = geo.size.width
      let segments = computeSegments(forWidth: totalWidth)
      HStack(spacing: 1) {
        ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
          Rectangle()
            .fill(seg.color)
            .frame(width: max(seg.width, 0))
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 2.5))
    }
    .frame(height: 5)
  }

  private var appRows: some View {
    VStack(spacing: 4) {
      ForEach(topApps) { entry in
        AppListRow(
          entry: entry,
          isSelected: selectedBundleId == entry.bundleId,
          fractionOfLongest: fractionOfLongest(for: entry),
          percentOfDay: percentOfDay(for: entry),
          onTap: { selectedBundleId = entry.bundleId }
        )
      }
      if remainingAppCount > 0 {
        otherAppsFooter
      }
    }
  }

  private var topApps: [AppUsageEntry] {
    Array(entries.prefix(visibleRowCutoff))
  }

  private var remainingAppCount: Int {
    max(0, entries.count - topApps.count)
  }

  private var dayTotalSeconds: Int {
    max(entries.reduce(0) { $0 + $1.totalSeconds }, 1)
  }

  private var longestAppSeconds: Int {
    max(entries.first?.totalSeconds ?? 1, 1)
  }

  private func fractionOfLongest(for entry: AppUsageEntry) -> Double {
    Double(entry.totalSeconds) / Double(longestAppSeconds)
  }

  private func percentOfDay(for entry: AppUsageEntry) -> Double {
    Double(entry.totalSeconds) / Double(dayTotalSeconds)
  }

  private var otherAppsFooter: some View {
    VStack(spacing: 0) {
      Rectangle()
        .fill(Color(hex: "ECECEC"))
        .frame(height: 1)
        .padding(.vertical, 4)
      HStack {
        Text("\(remainingAppCount) other app\(remainingAppCount == 1 ? "" : "s")")
          .font(.custom("Figtree", size: 12).weight(.medium))
          .foregroundColor(Color(hex: "8A8278"))
        Spacer()
      }
      .padding(.vertical, 6)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Text(isLoading ? "Loading…" : "No app activity for \(rangeLabel)")
        .font(.custom("Figtree", size: 13).weight(.medium))
        .foregroundColor(Color(hex: "8A8278"))
      if !isLoading {
        Text("Apps appear once you've been recording for a few minutes.")
          .font(.custom("Figtree", size: 11))
          .foregroundColor(Color(hex: "AFA7A0"))
          .multilineTextAlignment(.center)
      }
    }
  }

  private var totalLabel: String {
    formatHoursMinutes(seconds: entries.reduce(0) { $0 + $1.totalSeconds })
  }

  private var subtitleLabel: String {
    let count = entries.count
    let suffix = count == 1 ? "app" : "apps"
    return "active \(rangeLabel) · \(count) \(suffix) used"
  }

  // Top 5 apps + "other" segment, sized in proportion to total active time.
  private func computeSegments(forWidth width: CGFloat)
    -> [(color: Color, width: CGFloat)]
  {
    let total = max(entries.reduce(0) { $0 + $1.totalSeconds }, 1)
    let top5 = Array(entries.prefix(5))
    let otherSeconds = max(0, total - top5.reduce(0) { $0 + $1.totalSeconds })
    var result: [(Color, CGFloat)] = []
    for (i, e) in top5.enumerated() {
      let frac = CGFloat(e.totalSeconds) / CGFloat(total)
      result.append((segmentPalette[i % segmentPalette.count], frac * width))
    }
    if otherSeconds > 0 {
      let frac = CGFloat(otherSeconds) / CGFloat(total)
      result.append((otherColor, frac * width))
    }
    return result
  }
}

private struct AppListRow: View {
  let entry: AppUsageEntry
  let isSelected: Bool
  let fractionOfLongest: Double
  let percentOfDay: Double
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 12) {
        iconView
          .frame(width: 28, height: 28)
          .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

        VStack(alignment: .leading, spacing: 3) {
          HStack(alignment: .firstTextBaseline) {
            Text(entry.appName)
              .font(.custom("Figtree", size: 13).weight(.semibold))
              .foregroundColor(.black)
            Spacer(minLength: 8)
            Text(durationLabel)
              .font(.custom("Figtree", size: 11).weight(.semibold))
              .foregroundColor(Color(hex: "6B6560"))
          }

          GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
              Capsule()
                .fill(Color(hex: "F1ECE7"))
                .frame(height: 4)
              Capsule()
                .fill(isSelected ? Color(hex: "F96E00") : Color(hex: "FFA777"))
                .frame(width: max(2, w * CGFloat(fractionOfLongest)), height: 4)
            }
          }
          .frame(height: 4)
        }

        Text(percentLabel)
          .font(.custom("Figtree", size: 10.5).weight(.semibold))
          .foregroundColor(isSelected ? Color(hex: "F96E00") : Color(hex: "C5BDB8"))
          .frame(width: 38, alignment: .trailing)
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 10)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(isSelected ? Color(hex: "FFEFE4") : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var iconView: some View {
    if let nsImage = AppIconCache.shared.icon(forBundleId: entry.bundleId) {
      Image(nsImage: nsImage)
        .resizable()
        .interpolation(.high)
        .scaledToFit()
    } else {
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(Color(hex: "F1ECE7"))
        .overlay(
          Image(systemName: "app.fill")
            .font(.system(size: 12))
            .foregroundColor(Color(hex: "C5BDB8"))
        )
    }
  }

  private var durationLabel: String {
    formatHoursMinutes(seconds: entry.totalSeconds)
  }

  private var percentLabel: String {
    let pct = Int((percentOfDay * 100).rounded())
    return "\(pct)%"
  }
}

// MARK: - Shared formatters

func formatHoursMinutes(seconds: Int) -> String {
  if seconds < 60 { return "\(seconds)s" }
  let totalMinutes = seconds / 60
  let h = totalMinutes / 60
  let m = totalMinutes % 60
  if h == 0 { return "\(m)m" }
  return "\(h)h \(m)m"
}
