import SwiftUI

struct MarketSectionView: View {
    @ObservedObject var service: MarketService
    @ObservedObject private var preferences = DashboardPreferences.shared
    @Environment(\.compactSidebarSections) private var compact
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 0)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            SectionTitle(text: "Market")
            LazyVGrid(columns: columns, alignment: .leading, spacing: compact ? 3 : 7) {
                ForEach(preferences.marketInstruments) { instrument in
                    MarketQuoteCell(
                        instrument: instrument,
                        quote: service.quotes.first { $0.symbol == instrument.symbol },
                        delayed: service.isDelayed(service.quotes.first { $0.symbol == instrument.symbol })
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, compact ? 4 : 9)
    }
}

private struct MarketQuoteCell: View {
    let instrument: MarketInstrument
    let quote: MarketQuote?
    let delayed: Bool

    var body: some View {
        HStack(spacing: 3) {
            Text(instrument.name)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(width: 52, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .overlay(alignment: .topTrailing) {
                    if delayed {
                        Circle().fill(.secondary).frame(width: 3, height: 3)
                            .accessibilityLabel("Quote update delayed")
                    }
                }
            Text(quote.map { $0.value.formatted(.number.precision(.fractionLength(instrument.fractionDigits))) } ?? "—")
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Group {
                if let quote {
                    Text(quote.changePercent, format: .percent.precision(.fractionLength(2)).scale(1).sign(strategy: .always(includingZero: false)))
                        .foregroundStyle(changeColor(for: quote.changePercent))
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 38, alignment: .trailing)
        }
        .font(.system(size: 10))
        .help(freshnessDescription)
    }

    private var freshnessDescription: String {
        let title = "\(instrument.displayName) · \(instrument.detail)"
        guard let quote else { return title + "\nTemporarily unavailable. Retrying automatically." }
        var text = title + "\nFetched \(quote.updatedAt.formatted(date: .abbreviated, time: .shortened))"
        if let marketTime = quote.marketTime { text += "\nMarket quote: \(marketTime.formatted(date: .abbreviated, time: .shortened))" }
        if delayed { text += "\nUpdates delayed. Showing the last successful value." }
        return text
    }

    private func changeColor(for percent: Double) -> Color {
        guard percent != 0 else { return .secondary }
        let color: NSColor = percent > 0 ? .systemRed : .systemBlue
        return Color(nsColor: color.blended(withFraction: 0.3, of: .secondaryLabelColor) ?? color)
    }
}
