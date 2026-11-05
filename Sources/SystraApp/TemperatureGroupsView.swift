import SwiftUI

struct TemperatureGroupsView: View {
    let readings: [TemperatureReading]
    var compact = false
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(temperatureGroups(readings)) { group in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: group.component.symbol).foregroundStyle(.pink).frame(width: 22)
                        Text(group.component.title).font(.system(size: compact ? 13 : 14, weight: .semibold))
                        Spacer(minLength: 8)
                        Text(degrees(group.maximum)).font(.system(size: compact ? 17 : 21, weight: .semibold)).monospacedDigit()
                            .help(L("Максимальное показание среди датчиков этой группы, а не средняя температура компонента."))
                    }
                    Text(group.component.detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(L("Диапазон: {0} – {1} · максимум справа", String(describing: degrees(group.minimum)), String(describing: degrees(group.maximum))))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    DisclosureGroup(L("Отдельные датчики · {0}", String(describing: group.readings.count))) {
                        VStack(spacing: 0) {
                            ForEach(Array(group.readings.enumerated()), id: \.element.id) { index, reading in
                                HStack {
                                    Text("\(group.component.pointTitle) \(index + 1)")
                                    Spacer()
                                    Text(degrees(reading.value)).monospacedDigit()
                                }.font(.system(size: 12)).padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                    .help(L("Название macOS: {0}\nИсточник: {1}\n{2}", String(describing: reading.name), String(describing: reading.id), String(describing: group.component.detail)))
                            }
                        }.padding(.leading, 6).padding(.top, 4)
                    }.font(.system(size: 12)).tint(.secondary)
                }.padding(compact ? 12 : 14)
                    .instrumentSurface()
            }
            if readings.isEmpty { Text(L("macOS не предоставила доступных датчиков.")).font(.callout).foregroundStyle(.secondary).padding(12) }
        }
    }
}
