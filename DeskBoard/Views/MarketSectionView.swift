import SwiftUI

struct MarketSectionView: View {
    @ObservedObject var service: MarketService
    private let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 0)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Market")
            if service.quotes.isEmpty {
                PlaceholderText(text: "Market unavailable")
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
                    ForEach(service.quotes) { quote in
                        MarketQuoteCell(quote: quote)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }
}

private struct MarketQuoteCell: View {
    let quote: MarketQuote

    var body: some View {
        HStack(spacing: 6) {
            Text(quote.name)
                .frame(width: 47, alignment: .leading)
                .lineLimit(1)
            Text(quote.value.formatted(.number.precision(.fractionLength(2))))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 2)
            Text(quote.changePercent, format: .percent.precision(.fractionLength(2)).scale(1))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(quote.changePercent >= 0 ? Color(nsColor: .systemRed) : Color(nsColor: .systemBlue))
        }
        .font(.system(size: 10))
    }
}
