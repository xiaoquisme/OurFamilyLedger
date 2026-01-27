import Foundation

extension Bundle {
    /// Marketing version (e.g., "0.1.2")
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// Build number (e.g., "6")
    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// Full version string (e.g., "0.1.2 (6)")
    var fullVersionString: String {
        "\(appVersion) (\(buildNumber))"
    }
}
