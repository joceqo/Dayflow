import SwiftUI

struct AppUsageView: View {
  let date: Date
  @State private var samples: [AppUsageSample] = []
  @State private var segments: [AppActivitySegment] = []
  @State private var hoverInfo: HoverInfo? = nil

  private static let hiddenBundles: Set<String> = [
    "com.apple.loginwindow",
    "loginwindow",
    "com.apple.WindowManager",
    "com.apple.dock",
    "com.apple.notificationcenterui",
    "com.apple.controlcenter",
    "com.apple.systemuiserver",
  ]

  private var filteredSamples: [AppUsageSample] {
    samples.filter { sample in
      if let bid = sample.bundleIdentifier, Self.hiddenBundles.contains(bid) { return false }
      return !Self.hiddenBundles.contains(sample.appName)
    }
  }

  private var filteredSegments: [AppActivitySegment] {
    segments.filter { seg in
      if let bid = seg.bundleId, Self.hiddenBundles.contains(bid) { return false }
      return !Self.hiddenBundles.contains(seg.appName)
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if !filteredSegments.isEmpty {
          TimelineStripView(
            segments: filteredSegments,
            date: date,
            hoverInfo: $hoverInfo
          )
          .padding(.horizontal, 16)
          .padding(.top, 12)
        }

        if filteredSamples.isEmpty {
          VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
              .font(.system(size: 28))
              .foregroundStyle(Color(hex: "C8B8AF"))
            Text("No app usage data yet")
              .font(.custom("Nunito", size: 14))
              .foregroundStyle(Color(hex: "C8B8AF"))
            Text("Switch between apps — every activation is tracked with precise timestamps.")
              .font(.custom("Nunito", size: 12))
              .foregroundStyle(Color(hex: "C8B8AF").opacity(0.7))
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity, minHeight: 200)
        } else {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(filteredSamples) { sample in
              AppUsageRow(sample: sample, maxDuration: filteredSamples.first?.duration ?? 1)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
          }
          .padding(.bottom, 24)
        }
      }
    }
    .onAppear { reload() }
    .onChange(of: date) { _, _ in reload() }
    .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
      reload()
    }
  }

  private func reload() {
    let captureDate = date
    DispatchQueue.global(qos: .userInitiated).async {
      let usage = StorageManager.shared.appUsageForDay(captureDate)
      let cal = Calendar.current
      let start = cal.startOfDay(for: captureDate)
      let end = cal.date(byAdding: .hour, value: 28, to: start) ?? captureDate
      let segs = StorageManager.shared.fetchAppActivitySegments(
        startTs: Int(start.timeIntervalSince1970), endTs: Int(end.timeIntervalSince1970))
      DispatchQueue.main.async {
        samples = usage
        segments = segs
      }
    }
  }
}

// MARK: - Timeline strip

private struct HoverInfo: Equatable {
  let appName: String
  let startTs: Int
  let endTs: Int
  let x: CGFloat
}

private struct TimelineStripView: View {
  let segments: [AppActivitySegment]
  let date: Date
  @Binding var hoverInfo: HoverInfo?

  private var dayStart: Date { Calendar.current.startOfDay(for: date) }
  private var dayEnd: Date {
    Calendar.current.date(byAdding: .hour, value: 24, to: dayStart) ?? date
  }
  private var dayStartTs: Int { Int(dayStart.timeIntervalSince1970) }
  private var dayDurationSeconds: Double { 24 * 3600 }

  private let stripHeight: CGFloat = 34
  private let rowHeight: CGFloat = 72

  private var visibleSegments: [AppActivitySegment] {
    segments.filter { Double($0.endTs - $0.startTs) >= 1 }
  }

  private var hourLabels: [Int] { [0, 3, 6, 9, 12, 15, 18, 21] }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Timeline")
        .font(.custom("Nunito-SemiBold", size: 12))
        .foregroundStyle(Color(hex: "6E5B54"))

      GeometryReader { geo in
        ZStack(alignment: .topLeading) {
          // Hour grid
          ForEach(hourLabels, id: \.self) { h in
            let x = CGFloat(h) / 24 * geo.size.width
            Rectangle()
              .fill(Color(hex: "E8D9CE").opacity(0.55))
              .frame(width: 1, height: stripHeight)
              .offset(x: x, y: 0)
          }

          // Background
          RoundedRectangle(cornerRadius: 6)
            .fill(Color(hex: "F5ECE4"))
            .frame(height: stripHeight)

          // Segments
          ForEach(visibleSegments) { seg in
            segmentRect(seg, width: geo.size.width)
          }

          // Current time indicator (if today)
          if Calendar.current.isDateInToday(date) {
            let nowFraction =
              Date().timeIntervalSince(dayStart) / dayDurationSeconds
            let clamped = max(0, min(1, nowFraction))
            Rectangle()
              .fill(Color(hex: "D84315"))
              .frame(width: 1.5, height: stripHeight + 4)
              .offset(x: CGFloat(clamped) * geo.size.width - 0.75, y: -2)
          }
        }
        .frame(height: stripHeight)
      }
      .frame(height: stripHeight)

      // Hour ruler
      GeometryReader { geo in
        ZStack(alignment: .topLeading) {
          ForEach(hourLabels, id: \.self) { h in
            let x = CGFloat(h) / 24 * geo.size.width
            Text(hourLabel(h))
              .font(.system(size: 9, weight: .medium, design: .monospaced))
              .foregroundStyle(Color(hex: "9E8880"))
              .offset(x: x - 10, y: 0)
          }
        }
      }
      .frame(height: 12)

      // Hover tooltip
      if let hover = hoverInfo {
        hoverTooltip(hover)
          .transition(.opacity)
      }
    }
  }

  @ViewBuilder
  private func segmentRect(_ seg: AppActivitySegment, width: CGFloat) -> some View {
    let startOffset = max(0, Double(seg.startTs - dayStartTs))
    let endOffset = min(dayDurationSeconds, Double(seg.endTs - dayStartTs))
    if endOffset > startOffset {
      let x = CGFloat(startOffset / dayDurationSeconds) * width
      let w = max(1, CGFloat((endOffset - startOffset) / dayDurationSeconds) * width)

      Rectangle()
        .fill(AppColorPalette.color(for: seg.bundleId ?? seg.appName))
        .frame(width: w, height: stripHeight)
        .offset(x: x, y: 0)
        .onHover { inside in
          if inside {
            hoverInfo = HoverInfo(
              appName: seg.appName, startTs: seg.startTs, endTs: seg.endTs, x: x + w / 2)
          } else if hoverInfo?.appName == seg.appName, hoverInfo?.startTs == seg.startTs {
            hoverInfo = nil
          }
        }
    }
  }

  private static let tooltipFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "h:mm a"
    return f
  }()

  private func hoverTooltipText(_ info: HoverInfo) -> String {
    let startStr = Self.tooltipFormatter.string(
      from: Date(timeIntervalSince1970: TimeInterval(info.startTs)))
    let endStr = Self.tooltipFormatter.string(
      from: Date(timeIntervalSince1970: TimeInterval(info.endTs)))
    let durSec = max(0, info.endTs - info.startTs)
    let m = durSec / 60
    let s = durSec % 60
    let durStr = m > 0 ? "\(m)m \(s)s" : "\(s)s"
    return "· \(startStr) — \(endStr) · \(durStr)"
  }

  @ViewBuilder
  private func hoverTooltip(_ info: HoverInfo) -> some View {
    HStack(spacing: 6) {
      Text(info.appName)
        .font(.custom("Nunito-SemiBold", size: 11))
        .foregroundStyle(Color(hex: "2E221B"))
      Text(hoverTooltipText(info))
        .font(.custom("Nunito", size: 11))
        .foregroundStyle(Color(hex: "6E5B54"))
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(Color(hex: "FDF7F0"))
    .cornerRadius(6)
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .stroke(Color(hex: "E8D9CE"), lineWidth: 0.5))
  }

  private func hourLabel(_ hour: Int) -> String {
    if hour == 0 { return "12A" }
    if hour == 12 { return "12P" }
    if hour < 12 { return "\(hour)A" }
    return "\(hour - 12)P"
  }
}

// MARK: - Color palette

private enum AppColorPalette {
  private static let palette: [String] = [
    "#E07A5F",  // terracotta
    "#81B29A",  // sage
    "#F2CC8F",  // amber
    "#3D5A80",  // deep blue
    "#98C1D9",  // sky
    "#EE6C4D",  // coral
    "#B56576",  // rose
    "#6D597A",  // plum
    "#355070",  // navy
    "#E29578",  // peach
    "#83C5BE",  // mint
    "#C9ADA7",  // mauve
  ]

  static func color(for key: String) -> Color {
    var hash: UInt64 = 5381
    for byte in key.utf8 {
      hash = ((hash << 5) &+ hash) &+ UInt64(byte)
    }
    let idx = Int(hash % UInt64(palette.count))
    return Color(hex: palette[idx])
  }
}

// MARK: - App row (unchanged behavior)

private struct AppUsageRow: View {
  let sample: AppUsageSample
  let maxDuration: TimeInterval
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        AppIconView(bundleIdentifier: sample.bundleIdentifier)
        Text(sample.appName)
          .font(.custom("Nunito-SemiBold", size: 13))
          .foregroundStyle(Color(hex: "2E221B"))
          .lineLimit(1)
        Spacer()
        Text(formattedDuration(sample.duration))
          .font(.system(size: 12, weight: .medium, design: .monospaced))
          .foregroundStyle(Color(hex: "9E8880"))
        if !sample.topSites.isEmpty {
          Image(systemName: expanded ? "chevron.up" : "chevron.down")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color(hex: "C8B8AF"))
        }
      }
      .contentShape(Rectangle())
      .onTapGesture {
        guard !sample.topSites.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
      }

      GeometryReader { geo in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 3)
            .fill(Color(hex: "F0E8E4"))
            .frame(height: 5)
          RoundedRectangle(cornerRadius: 3)
            .fill(AppColorPalette.color(for: sample.bundleIdentifier ?? sample.appName))
            .frame(width: geo.size.width * CGFloat(sample.duration / maxDuration), height: 5)
        }
      }
      .frame(height: 5)

      if expanded && !sample.topSites.isEmpty {
        let sitesMax = sample.topSites.first?.duration ?? 1
        VStack(alignment: .leading, spacing: 3) {
          ForEach(sample.topSites, id: \.domain) { site in
            HStack(spacing: 6) {
              Text(site.domain)
                .font(.custom("Nunito", size: 11))
                .foregroundStyle(Color(hex: "6E5B54"))
                .lineLimit(1)
              Spacer()
              Text(formattedDuration(site.duration))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "B0A09A"))
            }
            GeometryReader { geo in
              RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: "C87941").opacity(0.35))
                .frame(width: geo.size.width * CGFloat(site.duration / sitesMax), height: 3)
            }
            .frame(height: 3)
          }
        }
        .padding(.leading, 26)
        .padding(.top, 2)
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .padding(.vertical, 4)
  }

  private func formattedDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return "\(m)m" }
    return "\(s)s"
  }
}

private struct AppIconView: View {
  let bundleIdentifier: String?
  @State private var icon: NSImage? = nil

  var body: some View {
    Group {
      if let icon {
        Image(nsImage: icon)
          .resizable()
          .interpolation(.high)
          .frame(width: 18, height: 18)
      } else {
        Image(systemName: "app.fill")
          .font(.system(size: 14))
          .foregroundStyle(Color(hex: "C8B8AF"))
          .frame(width: 18, height: 18)
      }
    }
    .onAppear { loadIcon() }
    .onChange(of: bundleIdentifier) { _, _ in loadIcon() }
  }

  private func loadIcon() {
    guard let bundle = bundleIdentifier,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
    else { return }
    icon = NSWorkspace.shared.icon(forFile: url.path)
  }
}
