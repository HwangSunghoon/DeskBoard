import SwiftUI

struct MarketSectionView: View {
    @ObservedObject var service: MarketService

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionTitle(text: "Market")
            if service.quotes.isEmpty {
                PlaceholderText(text: "Market unavailable")
            } else {
                ForEach(service.quotes) { quote in
                    HStack(spacing: 8) {
                        Text(quote.name).frame(width: 58, alignment: .leading)
                        Text(quote.value.formatted(.number.precision(.fractionLength(2))))
                            .monospacedDigit()
                        Spacer(minLength: 4)
                        Text(quote.changePercent, format: .percent.precision(.fractionLength(2)).scale(1))
                            .monospacedDigit()
                            .foregroundStyle(quote.changePercent >= 0 ? Color(nsColor: .systemRed) : Color(nsColor: .systemBlue))
                    }
                    .font(.system(size: 11))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }
}
