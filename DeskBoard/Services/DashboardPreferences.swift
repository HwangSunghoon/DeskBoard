import Combine
import Foundation
import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable, Codable {
    case today, worldClock, system, market, todo, focusTimer, important, memo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .worldClock: "World Clock"
        case .focusTimer: "Focus Timer"
        default: rawValue.capitalized
        }
    }
}

enum MarketInstrument: String, CaseIterable, Identifiable, Codable {
    case kospi, kosdaq, sp500, nasdaq, usdkrw, eurkrw
    case dow, ftse, dax, nikkei, hangSeng, eurusd, gold, wti, bitcoin

    static let defaults: [Self] = [.kospi, .kosdaq, .sp500, .nasdaq, .usdkrw, .eurkrw]
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .kospi: "^KS11"
        case .kosdaq: "^KQ11"
        case .sp500: "^GSPC"
        case .nasdaq: "^IXIC"
        case .usdkrw: "KRW=X"
        case .eurkrw: "EURKRW=X"
        case .dow: "^DJI"
        case .ftse: "^FTSE"
        case .dax: "^GDAXI"
        case .nikkei: "^N225"
        case .hangSeng: "^HSI"
        case .eurusd: "EURUSD=X"
        case .gold: "GC=F"
        case .wti: "CL=F"
        case .bitcoin: "BTC-USD"
        }
    }
    var name: String {
        switch self {
        case .kospi: "KOSPI"
        case .kosdaq: "KOSDAQ"
        case .sp500: "S&P 500"
        case .nasdaq: "NASDAQ"
        case .usdkrw: "USD/KRW"
        case .eurkrw: "EUR/KRW"
        case .dow: "Dow"
        case .ftse: "FTSE 100"
        case .dax: "DAX"
        case .nikkei: "Nikkei 225"
        case .hangSeng: "Hang Seng"
        case .eurusd: "EUR/USD"
        case .gold: "Gold"
        case .wti: "WTI"
        case .bitcoin: "Bitcoin"
        }
    }

    var displayName: String {
        switch self {
        case .nasdaq: "Nasdaq Composite"
        case .dow: "Dow Jones"
        case .gold: "Gold Futures"
        case .wti: "WTI Crude Futures"
        default: name
        }
    }

    var category: MarketCategory {
        switch self {
        case .sp500, .nasdaq, .dow: .usIndices
        case .ftse, .dax: .europeIndices
        case .kospi, .kosdaq, .nikkei, .hangSeng: .asiaIndices
        case .usdkrw, .eurkrw, .eurusd: .currencies
        case .gold, .wti: .commodities
        case .bitcoin: .crypto
        }
    }

    var detail: String {
        switch self {
        case .gold: "Futures · USD / troy oz"
        case .wti: "Futures · USD / barrel"
        case .bitcoin: "BTC / USD"
        case .usdkrw: "KRW per 1 USD"
        case .eurkrw: "KRW per 1 EUR"
        case .eurusd: "USD per 1 EUR"
        default: category.rawValue
        }
    }

    var fractionDigits: Int { self == .eurusd ? 4 : 2 }
}

enum MarketCategory: String, CaseIterable, Identifiable {
    case usIndices = "US Indices"
    case europeIndices = "European Indices"
    case asiaIndices = "Asian Indices"
    case currencies = "Currencies"
    case commodities = "Commodities"
    case crypto = "Crypto"
    var id: String { rawValue }
}

@MainActor
final class DashboardPreferences: ObservableObject {
    static let shared = DashboardPreferences()
    @Published private(set) var visibleSections: Set<DashboardSection>
    @Published private(set) var sectionOrder: [DashboardSection]
    @Published private(set) var marketInstruments: [MarketInstrument]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.stringArray(forKey: "visibleSections.v1") {
            visibleSections = Set(stored.compactMap(DashboardSection.init(rawValue:))).union([.memo])
        } else {
            visibleSections = [.memo]
        }
        var order: [DashboardSection] = []
        for key in defaults.stringArray(forKey: "sectionOrder.v1") ?? [] {
            if let section = DashboardSection(rawValue: key), !order.contains(section) {
                order.append(section)
            }
        }
        // Keep saved positions while appending sections added in later versions.
        sectionOrder = order + DashboardSection.allCases.filter { !order.contains($0) }
        var instruments: [MarketInstrument] = []
        for key in defaults.stringArray(forKey: "marketInstruments.v1") ?? [] {
            if let instrument = MarketInstrument(rawValue: key), !instruments.contains(instrument) {
                instruments.append(instrument)
            }
        }
        marketInstruments = instruments.count >= 2 ? Array(instruments.prefix(6)) : MarketInstrument.defaults
    }

    var orderedVisibleSections: [DashboardSection] {
        sectionOrder.filter(visibleSections.contains)
    }

    func moveSection(_ section: DashboardSection, by offset: Int) {
        guard offset == -1 || offset == 1,
              let index = sectionOrder.firstIndex(of: section),
              sectionOrder.indices.contains(index + offset) else { return }
        sectionOrder.swapAt(index, index + offset)
        defaults.set(sectionOrder.map(\.rawValue), forKey: "sectionOrder.v1")
    }

    func moveSections(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty, source.allSatisfy(sectionOrder.indices.contains),
              (0...sectionOrder.count).contains(destination) else { return }
        sectionOrder.move(fromOffsets: source, toOffset: destination)
        defaults.set(sectionOrder.map(\.rawValue), forKey: "sectionOrder.v1")
    }

    func setVisible(_ section: DashboardSection, _ visible: Bool) {
        guard section != .memo else { return }
        if visible { visibleSections.insert(section) }
        else { visibleSections.remove(section) }
        defaults.set(DashboardSection.allCases.filter(visibleSections.contains).map(\.rawValue), forKey: "visibleSections.v1")
    }

    func setSelected(_ instrument: MarketInstrument, _ selected: Bool) {
        if selected, !marketInstruments.contains(instrument), marketInstruments.count < 6 {
            marketInstruments.append(instrument)
        } else if !selected, marketInstruments.count > 2 {
            marketInstruments.removeAll { $0 == instrument }
        }
        saveMarketSelection()
    }

    func moveInstrument(_ instrument: MarketInstrument, by offset: Int) {
        guard let index = marketInstruments.firstIndex(of: instrument),
              marketInstruments.indices.contains(index + offset) else { return }
        marketInstruments.swapAt(index, index + offset)
        saveMarketSelection()
    }

    func moveInstruments(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty, source.allSatisfy(marketInstruments.indices.contains),
              (0...marketInstruments.count).contains(destination) else { return }
        marketInstruments.move(fromOffsets: source, toOffset: destination)
        saveMarketSelection()
    }

    private func saveMarketSelection() {
        defaults.set(marketInstruments.map(\.rawValue), forKey: "marketInstruments.v1")
    }
}
