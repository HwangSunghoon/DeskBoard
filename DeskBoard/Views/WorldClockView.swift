import SwiftUI

struct WorldClockView: View {
    @ObservedObject var store: WorldClockStore
    let now: Date
    @Environment(\.compactSidebarSections) private var compact

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            SectionTitle(text: "World Clock")
            if store.cities.isEmpty {
                Text("Choose cities in Settings")
                    .font(DashboardTypography.item)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(store.cities) { city in
                        VStack(alignment: .center, spacing: 2) {
                            Text(city.name)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(city.timeText(at: now))
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                                    .monospacedDigit()
                                    .fixedSize()
                                let offset = city.dayOffset(at: now)
                                if offset != 0 {
                                    Text(offset > 0 ? "+\(offset)d" : "\(offset)d")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .fixedSize()
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityElement(children: .combine)
                        .help(city.id)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, compact ? 2 : 8)
        .padding(.bottom, 4)
    }
}
