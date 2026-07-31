import AppKit

/// Checks whether an app is currently running, so a browser's cache or
/// cookies are never touched while it might have that data open.
public enum AppRunningCheck: Sendable {
    public static func isRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    public static let chromeBundleIdentifier = "com.google.Chrome"
    public static let safariBundleIdentifier = "com.apple.Safari"

    public static var isChromeRunning: Bool { isRunning(bundleIdentifier: chromeBundleIdentifier) }
    public static var isSafariRunning: Bool { isRunning(bundleIdentifier: safariBundleIdentifier) }
}
