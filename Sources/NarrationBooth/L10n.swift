import Foundation

/// UI language: English by default; Traditional Chinese when picked in the app (Language → 繁體中文).
let isChinese = UserDefaults.standard.string(forKey: "uiLanguage") == "zh"

func T(_ zh: String, _ en: String) -> String { isChinese ? zh : en }
