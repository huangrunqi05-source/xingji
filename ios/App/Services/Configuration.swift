import Foundation
import XingjiCore

enum Configuration {
    static var amapKey: String { value("AMapAPIKey") }
    static var hasMapKey: Bool { !amapKey.isEmpty && !amapKey.contains("YOUR_") && !amapKey.contains("$(") }
    static var cloudIdentifier: String? {
        guard value("CloudEnabled") == "YES" else { return nil }
        let id = value("CloudContainerIdentifier")
        return id.isEmpty || id.contains("$(") ? nil : id
    }
    private static func value(_ key: String) -> String { Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "" }
}
