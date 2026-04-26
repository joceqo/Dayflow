import ApplicationServices
import Foundation

/// Reads the current URL and window title from the frontmost browser window using the
/// Accessibility API. Returns nil silently when Accessibility permission is not granted.
enum BrowserURLReader {
  static let knownBrowserBundles: Set<String> = [
    "com.apple.Safari",
    "com.apple.SafariTechnologyPreview",
    "com.google.Chrome",
    "com.google.Chrome.canary",
    "org.mozilla.firefox",
    "com.microsoft.edgemac",
    "com.brave.Browser",
    "com.brave.Browser.nightly",
    "company.thebrowser.Browser",  // Arc
    "com.operasoftware.Opera",
    "com.vivaldi.Vivaldi",
    "com.kagi.kagimacOS",
  ]

  static func isBrowser(_ bundleId: String?) -> Bool {
    guard let bundleId else { return false }
    return knownBrowserBundles.contains(bundleId)
  }

  /// Returns (url, windowTitle) for a running application's focused window.
  /// Both values can be nil independently. Uses synchronous AX calls — call off main thread.
  static func read(pid: pid_t) -> (url: String?, windowTitle: String?) {
    guard AXIsProcessTrusted() else { return (nil, nil) }

    let axApp = AXUIElementCreateApplication(pid)
    var windowRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef)
      == .success,
      let axWindow = windowRef
    else { return (nil, nil) }

    let window = axWindow as! AXUIElement

    // Window title (works for all apps)
    var titleRef: CFTypeRef?
    let windowTitle: String? =
      AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success
      ? (titleRef as? String).flatMap { $0.isEmpty ? nil : $0 }
      : nil

    // URL via AXDocument (Safari, Chrome, most Chromium-based browsers)
    var docRef: CFTypeRef?
    let url: String? =
      AXUIElementCopyAttributeValue(window, "AXDocument" as CFString, &docRef) == .success
      ? (docRef as? String).flatMap { $0.isEmpty ? nil : $0 }
      : nil

    return (url: url, windowTitle: windowTitle)
  }

  /// Extracts the registrable domain from a URL string (e.g. "https://github.com/foo" → "github.com").
  static func domain(from urlString: String) -> String? {
    guard let url = URL(string: urlString), let host = url.host, !host.isEmpty else { return nil }
    // Strip leading "www."
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }
}
