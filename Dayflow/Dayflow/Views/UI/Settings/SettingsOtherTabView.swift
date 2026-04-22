import AppKit
import SwiftUI

struct SettingsOtherTabView: View {
  @ObservedObject var viewModel: OtherSettingsViewModel
  @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
  @FocusState private var isOutputLanguageFocused: Bool
  @State private var isIgnoredAppsExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      ignoredAppsCard
      SettingsCard(title: "App preferences", subtitle: "General toggles and telemetry settings") {
        VStack(alignment: .leading, spacing: 14) {
          Toggle(
            isOn: Binding(
              get: { launchAtLoginManager.isEnabled },
              set: { launchAtLoginManager.setEnabled($0) }
            )
          ) {
            Text("Launch Dayflow at login")
              .font(.custom("Nunito", size: 13))
              .foregroundColor(.black.opacity(0.7))
          }
          .toggleStyle(.switch)
          .pointingHandCursor()

          Text(
            "Keeps the menu bar controller running right after you sign in so capture can resume instantly."
          )
          .font(.custom("Nunito", size: 11.5))
          .foregroundColor(.black.opacity(0.5))

          Toggle(isOn: $viewModel.analyticsEnabled) {
            Text("Share crash reports and anonymous usage data")
              .font(.custom("Nunito", size: 13))
              .foregroundColor(.black.opacity(0.7))
          }
          .toggleStyle(.switch)
          .pointingHandCursor()

          Toggle(isOn: $viewModel.showDockIcon) {
            Text("Show Dock icon")
              .font(.custom("Nunito", size: 13))
              .foregroundColor(.black.opacity(0.7))
          }
          .toggleStyle(.switch)
          .pointingHandCursor()

          Text("When off, Dayflow runs as a menu bar-only app.")
            .font(.custom("Nunito", size: 11.5))
            .foregroundColor(.black.opacity(0.5))

          Toggle(isOn: $viewModel.showTimelineAppIcons) {
            Text("Show app/website icons in timeline")
              .font(.custom("Nunito", size: 13))
              .foregroundColor(.black.opacity(0.7))
          }
          .toggleStyle(.switch)
          .pointingHandCursor()

          Text("When off, timeline cards won't show app or website icons.")
            .font(.custom("Nunito", size: 11.5))
            .foregroundColor(.black.opacity(0.5))

          Toggle(isOn: $viewModel.saveAllTimelapsesToDisk) {
            Text("Save all timelapses to disk")
              .font(.custom("Nunito", size: 13))
              .foregroundColor(.black.opacity(0.7))
          }
          .toggleStyle(.switch)
          .pointingHandCursor()

          Text(
            "New and reprocessed timeline cards will pre-generate timelapse videos and store them on disk instead of building them on demand. Uses more storage and background processing."
          )
          .font(.custom("Nunito", size: 11.5))
          .foregroundColor(.black.opacity(0.5))
          .fixedSize(horizontal: false, vertical: true)

          VStack(alignment: .leading, spacing: 8) {
            Text("Output language override")
              .font(.custom("Nunito", size: 13))
              .foregroundColor(.black.opacity(0.7))
            HStack(spacing: 10) {
              TextField("English", text: $viewModel.outputLanguageOverride)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .frame(maxWidth: 220)
                .focused($isOutputLanguageFocused)
                .onChange(of: viewModel.outputLanguageOverride) {
                  viewModel.markOutputLanguageOverrideEdited()
                }
              DayflowSurfaceButton(
                action: {
                  viewModel.saveOutputLanguageOverride()
                  isOutputLanguageFocused = false
                },
                content: {
                  HStack(spacing: 6) {
                    Image(
                      systemName: viewModel.isOutputLanguageOverrideSaved
                        ? "checkmark" : "square.and.arrow.down"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    Text(viewModel.isOutputLanguageOverrideSaved ? "Saved" : "Save")
                      .font(.custom("Nunito", size: 12))
                  }
                  .padding(.horizontal, 2)
                },
                background: Color.white,
                foreground: Color(red: 0.25, green: 0.17, blue: 0),
                borderColor: Color(hex: "FFE0A5"),
                cornerRadius: 8,
                horizontalPadding: 12,
                verticalPadding: 7,
                showOverlayStroke: true
              )
              .disabled(viewModel.isOutputLanguageOverrideSaved)
              DayflowSurfaceButton(
                action: {
                  viewModel.resetOutputLanguageOverride()
                  isOutputLanguageFocused = false
                },
                content: {
                  Text("Reset")
                    .font(.custom("Nunito", size: 11))
                },
                background: Color.white,
                foreground: Color(red: 0.25, green: 0.17, blue: 0),
                borderColor: Color(hex: "FFE0A5"),
                cornerRadius: 8,
                horizontalPadding: 10,
                verticalPadding: 6,
                showOverlayStroke: true
              )
            }
            Text(
              "The default language is English. You can specify any language here (examples: English, 简体中文, Español, 日本語, 한국어, Français)."
            )
            .font(.custom("Nunito", size: 11.5))
            .foregroundColor(.black.opacity(0.5))
            .fixedSize(horizontal: false, vertical: true)
          }

          Text(
            "Dayflow v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")"
          )
          .font(.custom("Nunito", size: 12))
          .foregroundColor(.black.opacity(0.45))
        }
      }
    }
  }

  private var ignoredAppsCard: some View {
    VStack(alignment: .leading, spacing: isIgnoredAppsExpanded ? 18 : 0) {
      Button(action: {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
          isIgnoredAppsExpanded.toggle()
        }
      }) {
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Excluded apps")
              .font(.custom("Nunito", size: 18))
              .fontWeight(.semibold)
              .foregroundColor(.black.opacity(0.85))
            Text("Pause screenshots while these apps are frontmost")
              .font(.custom("Nunito", size: 12))
              .foregroundColor(.black.opacity(0.45))
          }
          Spacer(minLength: 0)
          Image(systemName: "chevron.down")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.black.opacity(0.55))
            .rotationEffect(.degrees(isIgnoredAppsExpanded ? 180 : 0))
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .pointingHandCursor()
      .help(isIgnoredAppsExpanded ? "Hide excluded apps" : "Show excluded apps")

      if isIgnoredAppsExpanded {
        VStack(alignment: .leading, spacing: 14) {
          Text(
            "When any of these apps is the active app, Dayflow won't take a screenshot for that moment and nothing will be tracked."
          )
          .font(.custom("Nunito", size: 11.5))
          .foregroundColor(.black.opacity(0.55))
          .fixedSize(horizontal: false, vertical: true)

          if viewModel.ignoredApps.isEmpty {
            Text("No apps excluded yet.")
              .font(.custom("Nunito", size: 12))
              .foregroundColor(.black.opacity(0.45))
              .padding(.vertical, 6)
          } else {
            VStack(spacing: 6) {
              ForEach(viewModel.ignoredApps) { app in
                ignoredAppRow(app)
              }
            }
          }

          HStack(spacing: 10) {
            DayflowSurfaceButton(
              action: { viewModel.presentAddIgnoredAppPanel() },
              content: {
                HStack(spacing: 6) {
                  Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                  Text("Add app…")
                    .font(.custom("Nunito", size: 12))
                }
                .padding(.horizontal, 2)
              },
              background: Color.white,
              foreground: Color(red: 0.25, green: 0.17, blue: 0),
              borderColor: Color(hex: "FFE0A5"),
              cornerRadius: 8,
              horizontalPadding: 12,
              verticalPadding: 7,
              showOverlayStroke: true
            )

            if let errorMessage = viewModel.ignoredAppErrorMessage {
              Text(errorMessage)
                .font(.custom("Nunito", size: 11.5))
                .foregroundColor(Color.red.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .padding(28)
    .background(
      RoundedRectangle(cornerRadius: 18)
        .fill(Color.white.opacity(0.72))
        .overlay(
          RoundedRectangle(cornerRadius: 18)
            .stroke(Color.white.opacity(0.55), lineWidth: 0.8)
        )
    )
  }

  private func ignoredAppRow(_ app: IgnoredApp) -> some View {
    HStack(spacing: 10) {
      if let icon = Self.appIcon(for: app.bundleId) {
        Image(nsImage: icon)
          .resizable()
          .interpolation(.high)
          .frame(width: 20, height: 20)
      } else {
        RoundedRectangle(cornerRadius: 4)
          .fill(Color.black.opacity(0.08))
          .frame(width: 20, height: 20)
      }

      VStack(alignment: .leading, spacing: 1) {
        Text(app.name)
          .font(.custom("Nunito", size: 13))
          .foregroundColor(.black.opacity(0.8))
        Text(app.bundleId)
          .font(.custom("Nunito", size: 11))
          .foregroundColor(.black.opacity(0.45))
      }

      Spacer()

      Button(action: { viewModel.removeIgnoredApp(bundleId: app.bundleId) }) {
        Image(systemName: "xmark")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.black.opacity(0.55))
          .padding(6)
          .background(
            Circle().fill(Color.black.opacity(0.05))
          )
      }
      .buttonStyle(.plain)
      .pointingHandCursor()
      .help("Remove \(app.name)")
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(Color.black.opacity(0.03))
    )
  }

  private static func appIcon(for bundleId: String) -> NSImage? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
    else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
  }
}
