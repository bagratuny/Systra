import Foundation

func decimal(_ value: Double, digits: Int = 1) -> String {
    guard value.isFinite else { return "—" }
    return String(format: "%.*f", locale: AppLanguage.current.locale, digits, value)
}
func bytes(_ value: UInt64) -> String {
    let units = [L("Б"), L("КБ"), L("МБ"), L("ГБ"), L("ТБ")]
    var amount = Double(value), unit = 0
    while amount >= 1024 && unit < units.count - 1 { amount /= 1024; unit += 1 }
    return (unit == 0 ? String(value) : decimal(amount)) + " " + units[unit]
}
func rate(_ value: Double?) -> String {
    guard let value, value.isFinite, value >= 0 else { return "—" }
    return bytes(UInt64(min(value, Double(Int64.max)))) + L("/с")
}
func percent(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return decimal(value) + "%"
}
func degrees(_ value: Double?) -> String {
    guard let value, value.isFinite else { return L("Недоступно") }
    return decimal(value) + " °C"
}

enum MetricDisplayUnit {
    case percentage, temperature, throughput
    func formatted(_ value: Double?) -> String {
        switch self {
        case .percentage: return percent(value)
        case .temperature: return degrees(value)
        case .throughput: return rate(value)
        }
    }
}
