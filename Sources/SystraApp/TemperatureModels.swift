import Foundation

struct TemperatureReading: Identifiable {
    let id: String
    /// Original macOS product name, retained for diagnostics.
    let name: String
    let value: Double
    var component: TemperatureComponent {
        let name = name.lowercased()
        if name.contains("battery") { return .battery }
        if name.contains("nand") || name.contains("ssd") { return .storage }
        if name.contains("gpu") { return .gpu }
        if name.contains("cpu") { return .cpu }
        if name.hasPrefix("pmu tdie") || name.contains("soc die") || name.contains("acc mtr") { return .chip }
        return .internalSensors
    }
}

enum TemperatureComponent: String, CaseIterable, Identifiable {
    case chip, cpu, gpu, battery, storage, internalSensors
    var id: String { rawValue }
    var title: String {
        switch self {
        case .chip: return "Чип Apple Silicon"
        case .cpu: return "Процессор"
        case .gpu: return "Графика"
        case .battery: return "Батарея"
        case .storage: return "Накопитель SSD"
        case .internalSensors: return "Внутренние датчики"
        }
    }
    var symbol: String {
        switch self {
        case .chip, .cpu: return "cpu"
        case .gpu: return "square.3.layers.3d"
        case .battery: return "battery.75"
        case .storage: return "internaldrive"
        case .internalSensors: return "thermometer.medium"
        }
    }
    var detail: String {
        switch self {
        case .chip: return "Температура в разных участках чипа. Точное соответствие ядрам macOS не сообщает."
        case .cpu: return "Датчики, обозначенные macOS как CPU."
        case .gpu: return "Датчики, обозначенные macOS как GPU."
        case .battery: return "Показания температурных датчиков батареи."
        case .storage: return "Температура датчиков накопителя; может отличаться от температуры его контроллера."
        case .internalSensors: return "Дополнительные точки измерения. Их точное расположение macOS не раскрывает."
        }
    }
    var pointTitle: String { self == .chip ? "Участок чипа" : "Датчик" }
}

struct TemperatureGroup: Identifiable {
    let component: TemperatureComponent
    let readings: [TemperatureReading]
    var id: TemperatureComponent { component }
    var maximum: Double { readings.map(\.value).max() ?? 0 }
    var minimum: Double { readings.map(\.value).min() ?? 0 }
}

func temperatureGroups(_ readings: [TemperatureReading]) -> [TemperatureGroup] {
    TemperatureComponent.allCases.compactMap { component in
        let matching = readings.filter { $0.component == component }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        return matching.isEmpty ? nil : TemperatureGroup(component: component, readings: matching)
    }
}
