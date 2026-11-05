import Foundation

@main struct LocalizationChecks {
    static func main() throws {
        let dictionary = Translations.english
        precondition(dictionary.count >= 360, "English resources must be bundled")
        let pattern = try NSRegularExpression(pattern: #"\{\d+\}|%[.0-9]*[f@]"#)
        func placeholders(_ text: String) -> [String] {
            pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) }.sorted()
        }
        for (key, value) in dictionary {
            precondition(!value.isEmpty && placeholders(key) == placeholders(value), "Mismatched translation: \(key)")
        }
        precondition(Translations.text("Выбрано: {0}", language: .english, arguments: ["{1}"]) == "Selected: {1}")
        precondition(Translations.text("Выбрано: {0}", language: .russian, arguments: ["2"]) == "Выбрано: 2")
        precondition(Translations.text("Unknown key", language: .english) == "Unknown key")
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "systra.language")
        defer {
            if let previous { defaults.set(previous, forKey: "systra.language") }
            else { defaults.removeObject(forKey: "systra.language") }
        }
        defaults.set("en", forKey: "systra.language")
        precondition(AppLanguage.current == .english)
        precondition(bytes(1536) == "1.5 KB" && rate(1024) == "1.0 KB/s")
        precondition(percent(12.5) == "12.5%" && degrees(nil) == "Unavailable")
        defaults.set("ru", forKey: "systra.language")
        precondition(bytes(1536) == "1,5 КБ" && rate(1024) == "1,0 КБ/с")
        print("PASS: translation coverage, format placeholders, literal arguments, live language and metric units")
    }
}
