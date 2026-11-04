import Foundation
@main struct TemperatureChecks {
    static func main() {
        let names: [(String, TemperatureComponent)] = [("PMU tdie1", .chip), ("SOC Die", .chip), ("pACC MTR Temp Sensor0", .chip), ("gas gauge battery", .battery), ("NAND CH0 temp", .storage), ("CPU core 1", .cpu), ("GPU die", .gpu), ("PMU TP3g", .internalSensors), ("PMU tdev2", .internalSensors), ("PMU tcal", .internalSensors), ("Unknown", .internalSensors)]
        for (name, expected) in names { precondition(TemperatureReading(id: name, name: name, value: 40).component == expected) }
        let readings = [TemperatureReading(id: "PMU tdie2-0", name: "PMU tdie2", value: 50), TemperatureReading(id: "PMU tdie1-1", name: "PMU tdie1", value: 30), TemperatureReading(id: "PMU tdie1-0", name: "PMU tdie1", value: 40), TemperatureReading(id: "battery-0", name: "gas gauge battery", value: 25)]
        let groups = temperatureGroups(readings)
        precondition(groups.count == 2 && groups[0].component == .chip)
        precondition(groups[0].maximum == 50 && groups[0].minimum == 30 && groups[0].readings.count == 3)
        precondition(groups[0].readings.first?.id == "PMU tdie1-0")
        precondition(temperatureGroups(Array(readings.reversed()))[0].readings.map(\.id) == groups[0].readings.map(\.id))
        precondition(temperatureGroups([]).isEmpty)
        print("Temperature checks: PASS; conservative names, duplicates, order, range and empty readings")
    }
}
