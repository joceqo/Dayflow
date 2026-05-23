import AppKit
import SwiftUI

struct AppInspectorView: View {
  let entry: AppUsageEntry?
  let totalDaySeconds: Int

  @State private var linkedCards: [TimelineCard] = []
  // Cache key: bundleId + sorted IDs. Refreshes triggered by the parent's
  // polling timer change `linkedCardIds` as new cards finish analysis; the
  // inspector must re-hydrate when that set grows even if bundleId is stable.
  @State private var loadedCacheKey: String? = nil

  var body: some View {
    ZStack {
      Color.white.opacity(0.7)

      Group {
        if let entry = entry {
          contentForEntry(entry)
        } else {
          emptyState
        }
      }
      .padding(20)
    }
    .clipShape(
      UnevenRoundedRectangle(
        cornerRadii: .init(
          topLeading: 0,
          bottomLeading: 0,
          bottomTrailing: 8,
          topTrailing: 8
        )
      )
    )
    .onAppear { reloadCardsIfNeeded() }
    .onChange(of: cacheKey) { _, _ in reloadCardsIfNeeded() }
  }

  private var cacheKey: String? {
    guard let entry = entry else { return nil }
    let ids = entry.linkedCardIds.sorted()
    return "\(entry.bundleId)#\(ids.map(String.init).joined(separator: ","))"
  }

  // MARK: - Empty state

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "square.grid.2x2")
        .font(.system(size: 28, weight: .regular))
        .foregroundColor(Color(hex: "C5BDB8"))
      Text("Select an app to see details")
        .font(.custom("Figtree", size: 12).weight(.medium))
        .foregroundColor(Color(hex: "8A8278"))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Entry content

  private func contentForEntry(_ entry: AppUsageEntry) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header(entry: entry)
        statsRow(entry: entry)

        Text("Activity cards")
          .font(.custom("Figtree", size: 9.5).weight(.bold))
          .tracking(0.8)
          .foregroundColor(Color(hex: "AFA7A0"))
          .textCase(.uppercase)

        cardsSection(entry: entry)

        Spacer(minLength: 16)
        instantNotice
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func header(entry: AppUsageEntry) -> some View {
    HStack(alignment: .center, spacing: 10) {
      appIcon(for: entry.bundleId)
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

      VStack(alignment: .leading, spacing: 2) {
        Text(entry.appName)
          .font(.custom("InstrumentSerif-Regular", size: 15))
          .foregroundColor(.black)
        Text(metaLabel(for: entry))
          .font(.custom("Figtree", size: 10.5))
          .foregroundColor(Color(hex: "8A8278"))
      }
      Spacer()
    }
  }

  @ViewBuilder
  private func appIcon(for bundleId: String) -> some View {
    if let nsImage = AppIconCache.shared.icon(forBundleId: bundleId) {
      Image(nsImage: nsImage)
        .resizable()
        .interpolation(.high)
        .scaledToFit()
    } else {
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(Color(hex: "F1ECE7"))
        .overlay(
          Image(systemName: "app.fill")
            .font(.system(size: 14))
            .foregroundColor(Color(hex: "C5BDB8"))
        )
    }
  }

  private func metaLabel(for entry: AppUsageEntry) -> String {
    let duration = formatHoursMinutes(seconds: entry.totalSeconds)
    let dayTotal = max(totalDaySeconds, 1)
    let pct = Int((Double(entry.totalSeconds) / Double(dayTotal) * 100).rounded())
    return "\(duration) · \(pct)% of today"
  }

  private func statsRow(entry: AppUsageEntry) -> some View {
    HStack(spacing: 8) {
      AppUsageStatBox(
        title: "Sessions",
        primary: "\(entry.sessionCount)",
        secondary: avgSessionLabel(for: entry)
      )
      AppUsageStatBox(
        title: "Longest",
        primary: formatHoursMinutes(seconds: entry.longestSessionSeconds),
        secondary: longestRangeLabel(for: entry)
      )
    }
  }

  private func avgSessionLabel(for entry: AppUsageEntry) -> String {
    guard entry.sessionCount > 0 else { return "—" }
    let avg = entry.totalSeconds / entry.sessionCount
    return "avg \(formatHoursMinutes(seconds: avg)) each"
  }

  private func longestRangeLabel(for entry: AppUsageEntry) -> String {
    guard entry.longestSessionSeconds > 0 else { return "—" }
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    let start = formatter.string(from: entry.longestSessionStart)
    let end = formatter.string(from: entry.longestSessionEnd)
    return "\(start) – \(end)"
  }

  // MARK: - Cards section

  private func cardsSection(entry: AppUsageEntry) -> some View {
    Group {
      if entry.linkedCardIds.isEmpty {
        Text("No activity cards yet")
          .font(.custom("Figtree", size: 11))
          .foregroundColor(Color(hex: "AFA7A0"))
      } else if linkedCards.isEmpty && loadedCacheKey == cacheKey {
        // IDs resolved but hydration returned nothing — most likely the cards
        // were soft-deleted between aggregation and inspector hydration.
        Text("Cards no longer available")
          .font(.custom("Figtree", size: 11))
          .foregroundColor(Color(hex: "AFA7A0"))
      } else {
        VStack(spacing: 6) {
          ForEach(linkedCards) { card in
            AppUsageMiniCard(card: card)
          }
        }
      }
    }
  }

  private var instantNotice: some View {
    HStack(alignment: .top, spacing: 6) {
      Image(systemName: "bolt.fill")
        .font(.system(size: 10))
        .foregroundColor(Color(hex: "F96E00"))
      Text("App times are instant — cards appear as analysis finishes.")
        .font(.custom("Figtree", size: 10.5))
        .foregroundColor(Color(hex: "8A8278"))
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color(hex: "FFF4EA"))
    )
  }

  // MARK: - Hydration

  private func reloadCardsIfNeeded() {
    guard let entry = entry else {
      linkedCards = []
      loadedCacheKey = nil
      return
    }
    let key = cacheKey
    if loadedCacheKey == key { return }
    let ids = entry.linkedCardIds
    loadedCacheKey = key
    guard !ids.isEmpty else {
      linkedCards = []
      return
    }

    Task.detached(priority: .userInitiated) {
      let fetched = StorageManager.shared.fetchTimelineCards(byIds: ids)
      await MainActor.run {
        guard loadedCacheKey == key else { return }
        linkedCards = fetched
      }
    }
  }
}

private struct AppUsageStatBox: View {
  let title: String
  let primary: String
  let secondary: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.custom("Figtree", size: 9.5).weight(.bold))
        .tracking(0.8)
        .foregroundColor(Color(hex: "AFA7A0"))
        .textCase(.uppercase)
      Text(primary)
        .font(.custom("InstrumentSerif-Regular", size: 18))
        .foregroundColor(.black)
      Text(secondary)
        .font(.custom("Figtree", size: 10.5))
        .foregroundColor(Color(hex: "8A8278"))
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.white)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color(hex: "ECECEC"), lineWidth: 1)
    )
  }
}

private struct AppUsageMiniCard: View {
  let card: TimelineCard

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Text("\(card.startTimestamp) – \(card.endTimestamp)")
        .font(.custom("Figtree", size: 9.5).weight(.semibold))
        .foregroundColor(Color(hex: "AFA7A0"))
        .frame(width: 78, alignment: .leading)
        .padding(.top, 1)

      VStack(alignment: .leading, spacing: 3) {
        if card.title.isEmpty {
          HStack(spacing: 5) {
            Circle()
              .fill(Color(hex: "F96E00"))
              .frame(width: 5, height: 5)
            Text("Analyzing…")
              .font(.custom("Figtree", size: 11).weight(.medium))
              .foregroundColor(Color(hex: "8A8278"))
          }
        } else {
          Text(card.title)
            .font(.custom("Figtree", size: 11).weight(.semibold))
            .foregroundColor(.black)
            .lineLimit(2)
        }
        Text(card.category)
          .font(.custom("Figtree", size: 9.5).weight(.semibold))
          .foregroundColor(Color(hex: "8A8278"))
          .padding(.horizontal, 5)
          .padding(.vertical, 1.5)
          .background(
            Capsule().fill(Color(hex: "F1ECE7"))
          )
      }
      Spacer(minLength: 0)
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(Color.white)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .stroke(Color(hex: "ECECEC"), lineWidth: 1)
    )
  }
}
