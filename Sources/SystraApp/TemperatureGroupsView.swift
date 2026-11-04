import SwiftUI

struct TemperatureGroupsView: View {
    let readings: [TemperatureReading]
    var compact = false
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(temperatureGroups(readings)) { group in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: group.component.symbol).foregroundStyle(.pink).frame(width: 22)
                        Text(group.component.title).font(.system(size: compact ? 13 : 14, weight: .semibold))
                        Spacer(minLength: 8)
                        Text(degrees(group.maximum)).font(.system(size: compact ? 17 : 21, weight: .semibold)).monospacedDigit()
                            .help("Максимальное показание среди датчиков этой группы, а не средняя температура компонента.")
                    }
                    Text(group.component.detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("Диапазон: \(degrees(group.minimum)) – \(degrees(group.maximum)) · максимум справа")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    DisclosureGroup("Отдельные датчики · \(group.readings.count)") {
                        VStack(spacing: 0) {
                            ForEach(Array(group.readings.enumerated()), id: \.element.id) { index, reading in
                                HStack {
                                    Text("\(group.component.pointTitle) \(index + 1)")
                                    Spacer()
                                    Text(degrees(reading.value)).monospacedDigit()
                                }.font(.system(size: 12)).padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                    .help("Название macOS: \(reading.name)\nИсточник: \(reading.id)\n\(group.component.detail)")
                            }
                        }.padding(.leading, 6).padding(.top, 4)
                    }.font(.system(size: 11)).tint(.secondary)
                }.padding(compact ? 12 : 14)
                    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if readings.isEmpty { Text("macOS не предоставила доступных датчиков.").font(.callout).foregroundStyle(.secondary).padding(12) }
        }
    }
}
