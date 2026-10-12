import Foundation

/// Interface languages. English and Traditional Chinese live in the source (every string is written as
/// `T("繁體中文", "English")`); every other language is a JSON file in `Localizations/<code>.json` that maps the English
/// text to its translation. To add a language: copy `Localizations/ja.json`, translate the values, add a case here.
enum UILanguage: String, CaseIterable {
    case en, zhHant = "zh", zhHans = "zh-Hans", ja, ko, es, fr, de

    /// Shown in the Language menu, always in the language itself.
    var nativeName: String {
        switch self {
        case .en: return "English"
        case .zhHant: return "繁體中文"
        case .zhHans: return "简体中文"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .es: return "Español"
        case .fr: return "Français"
        case .de: return "Deutsch"
        }
    }

    /// The language picked in the app, or else the first supported language in the Mac's preferred list, or English.
    static let current: UILanguage = {
        if let saved = UserDefaults.standard.string(forKey: "uiLanguage"), let l = UILanguage(rawValue: saved) { return l }
        for id in Locale.preferredLanguages {
            let lower = id.lowercased()
            if lower.hasPrefix("zh") {
                return lower.contains("hans") || lower.hasSuffix("-cn") || lower.hasSuffix("-sg") ? .zhHans : .zhHant
            }
            if let l = UILanguage(rawValue: String(lower.prefix(2))) { return l }
        }
        return .en
    }()
}

/// English text → translation, for the current language (empty for English and Traditional Chinese).
private let table: [String: String] = {
    let l = UILanguage.current
    guard l != .en, l != .zhHant,
          let url = Bundle.main.url(forResource: l.rawValue, withExtension: "json", subdirectory: "Localizations"),
          let data = try? Data(contentsOf: url),
          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
    return dict
}()

/// A UI string. `zh` is Traditional Chinese, `en` is English and the key for every other language. Strings with
/// values use `%@` placeholders (`%%` for a literal percent sign) and pass the values after.
func T(_ zh: String, _ en: String, _ args: CVarArg...) -> String {
    let s: String
    switch UILanguage.current {
    case .en: s = en
    case .zhHant: s = zh
    default: s = table[en].flatMap { $0.isEmpty ? nil : $0 } ?? en
    }
    return args.isEmpty ? s : String(format: s, arguments: args)
}
