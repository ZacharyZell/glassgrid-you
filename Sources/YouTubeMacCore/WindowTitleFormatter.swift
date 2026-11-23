import Foundation

/// Formats dynamic macOS window titles shown in the native Window menu, Mission Control, and Stage Manager
/// while the Liquid Glass window titlebar keeps `titleVisibility = .hidden`.
public enum WindowTitleFormatter {
    public static let appName = "GlassGrid You"

    public static func title(
        isMultiview: Bool,
        multiviewCount: Int,
        tabTitle: String,
        isHome: Bool
    ) -> String {
        if isMultiview && multiviewCount >= 2 {
            return "Multiview (\(multiviewCount) Streams) — \(appName)"
        }
        let cleaned = YouTubeTitleFormatter.clean(tabTitle)
        if isHome || cleaned.isEmpty || cleaned == "YouTube" || cleaned == appName {
            return appName
        }
        return "\(cleaned) — \(appName)"
    }
}
