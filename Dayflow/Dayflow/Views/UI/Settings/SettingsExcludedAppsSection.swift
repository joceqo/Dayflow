import AppKit
import SwiftUI

/// Section rendered inside `SettingsOtherTabView` that lets the user pick
/// apps whose screenshots should be skipped while they're frontmost.
/// Uses the v1.10 settings design system (`SettingsSection`, `SettingsRow`,
/// `SettingsSecondaryButton`) — no container chrome, label-left control-right.
struct SettingsExcludedAppsSection: View {
  @StateObject private var model = ExcludedAppsModel()

  var body: some View {
    SettingsSection(
      title: "Excluded apps",
      subtitle:
        "Dayflow skips capturing screenshots while any of these apps is frontmost. Useful for password managers, private browsers, or anything you don't want summarized."
    ) {
      VStack(alignment: .leading, spacing: 0) {
        if model.apps.isEmpty {
          HStack {
            Text("No apps excluded yet.")
              .font(.custom("Nunito", size: 13))
              .foregroundColor(SettingsStyle.secondary)
            Spacer()
          }
          .padding(.vertical, SettingsStyle.rowVerticalPadding)

          Rectangle()
            .fill(SettingsStyle.divider)
            .frame(height: 1)
        } else {
          ForEach(Array(model.apps.enumerated()), id: \.element.bundleId) { index, app in
            excludedAppRow(app, showsDivider: true)
          }
        }

        HStack(spacing: 8) {
          SettingsSecondaryButton(
            title: "Add app…",
            systemImage: "plus",
            action: { model.showAddPanel() }
          )
          if let error = model.errorMessage {
            Text(error)
              .font(.custom("Nunito", size: 12))
              .foregroundColor(SettingsStyle.destructive)
          }
          Spacer()
        }
        .padding(.top, 12)
      }
    }
  }

  @ViewBuilder
  private func excludedAppRow(_ app: IgnoredApp, showsDivider: Bool) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center, spacing: 12) {
        ExcludedAppIcon(bundleId: app.bundleId)
          .frame(width: 24, height: 24)

        VStack(alignment: .leading, spacing: 2) {
          Text(app.name)
            .font(.custom("Nunito", size: 14))
            .fontWeight(.semibold)
            .foregroundColor(SettingsStyle.text)
            .lineLimit(1)
          Text(app.bundleId)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(SettingsStyle.meta)
            .lineLimit(1)
        }

        Spacer(minLength: 12)

        SettingsSecondaryButton(
          title: "Remove",
          action: { model.remove(bundleId: app.bundleId) }
        )
      }
      .padding(.vertical, SettingsStyle.rowVerticalPadding)

      if showsDivider {
        Rectangle()
          .fill(SettingsStyle.divider)
          .frame(height: 1)
      }
    }
  }
}

private struct ExcludedAppIcon: View {
  let bundleId: String
  @State private var icon: NSImage?

  var body: some View {
    Group {
      if let icon {
        Image(nsImage: icon)
          .resizable()
          .interpolation(.high)
      } else {
        RoundedRectangle(cornerRadius: 5)
          .fill(Color.black.opacity(0.05))
          .overlay(
            Image(systemName: "app.fill")
              .font(.system(size: 12))
              .foregroundColor(SettingsStyle.meta)
          )
      }
    }
    .onAppear(perform: loadIcon)
    .onChange(of: bundleId) { _, _ in loadIcon() }
  }

  private func loadIcon() {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
    else { return }
    icon = NSWorkspace.shared.icon(forFile: url.path)
  }
}

@MainActor
final class ExcludedAppsModel: ObservableObject {
  @Published private(set) var apps: [IgnoredApp] = []
  @Published var errorMessage: String?

  private var observer: NSObjectProtocol?

  init() {
    reload()
    observer = NotificationCenter.default.addObserver(
      forName: IgnoredAppsPreferences.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.reload() }
    }
  }

  deinit {
    if let observer {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  private func reload() {
    apps = IgnoredAppsPreferences.apps
  }

  func remove(bundleId: String) {
    IgnoredAppsPreferences.remove(bundleId: bundleId)
  }

  func showAddPanel() {
    errorMessage = nil
    let panel = NSOpenPanel()
    panel.title = "Choose an app to exclude"
    panel.prompt = "Exclude"
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = [.application]
    let applicationsURL = URL(fileURLWithPath: "/Applications")
    if FileManager.default.fileExists(atPath: applicationsURL.path) {
      panel.directoryURL = applicationsURL
    }

    guard panel.runModal() == .OK, let url = panel.url else { return }

    guard let bundle = Bundle(url: url),
      let bundleId = bundle.bundleIdentifier,
      !bundleId.isEmpty
    else {
      errorMessage = "Couldn't read the bundle ID for that app."
      return
    }

    let name =
      (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
      ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
      ?? url.deletingPathExtension().lastPathComponent

    IgnoredAppsPreferences.add(IgnoredApp(bundleId: bundleId, name: name))
  }
}
