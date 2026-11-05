import Foundation

enum AppLanguage: String, CaseIterable {
    case russian = "ru", english = "en"
    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "systra.language") ?? "ru") ?? .russian
    }
    var locale: Locale { Locale(identifier: self == .english ? "en_US" : "ru_RU") }
}

enum Translations {
    static let english: [String: String] = {
        guard let url = Bundle.main.url(forResource: "English", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return values
    }()
    private static let placeholder = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)
    static func text(_ key: String, language: AppLanguage, arguments: [String] = []) -> String {
        let template = language == .english ? english[key] ?? key : key
        // Replace in one pass so user-controlled values containing {0} stay literal.
        var result = template
        for match in placeholder.matches(in: template, range: NSRange(template.startIndex..., in: template)).reversed() {
            guard let indexRange = Range(match.range(at: 1), in: template),
                  let index = Int(template[indexRange]), arguments.indices.contains(index),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: arguments[index])
        }
        return result
    }
}
func L(_ key: String, _ arguments: String...) -> String {
    Translations.text(key, language: .current, arguments: arguments)
}
