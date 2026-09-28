import Foundation

/// Uses Bundle's language negotiation, including macOS per-app language preferences.
struct Localizer {
    let bundle: Bundle
    init(bundle: Bundle = .main) { self.bundle = bundle }
    func text(_ key: String, _ arguments: CVarArg...) -> String { format(key, arguments) }
    func format(_ key: String, _ arguments: [CVarArg]) -> String {
        let english = bundle.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
        let fallback = english?.localizedString(forKey: key, value: key, table: nil) ?? key
        let value = bundle.localizedString(forKey: key, value: fallback, table: nil)
        return arguments.isEmpty ? value : String(format: value, arguments: arguments)
    }
}
enum L10n {
    #if HANDOFF_WATCHER_QA
    static var previewBundle: Bundle?
    #endif
    static var current: Localizer {
        #if HANDOFF_WATCHER_QA
        if let previewBundle { return Localizer(bundle: previewBundle) }
        #endif
        return Localizer()
    }
    static func text(_ key: String, _ arguments: CVarArg...) -> String { current.format(key, arguments) }
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
