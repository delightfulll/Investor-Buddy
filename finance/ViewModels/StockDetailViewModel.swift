//
//  StockDetailViewModel.swift
//  finance
//
//  MVVM: Stock detail – price history, company info, time range.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class StockDetailViewModel: ObservableObject {
    enum TimeRange: String, CaseIterable {
        case oneDay = "1D"
        case oneWeek = "1W"
        case oneMonth = "1M"
        case threeMonths = "3M"
        case yearToDate = "YTD"
        case oneYear = "1Y"

        var apiRange: String {
            switch self {
            case .oneDay: return "1d"
            case .oneWeek: return "5d"
            case .oneMonth: return "1mo"
            case .threeMonths: return "3mo"
            case .yearToDate: return "ytd"
            case .oneYear: return "1y"
            }
        }
        var apiInterval: String {
            switch self {
            case .oneDay: return "5m"
            case .oneWeek: return "15m"
            case .oneMonth: return "1d"
            case .threeMonths: return "1d"
            case .yearToDate: return "1d"
            case .oneYear: return "1d"
            }
        }
    }

    let stock: StockData
    @Published var selectedTimeRange: TimeRange = .oneMonth
    @Published var priceHistory: [PriceDataPoint] = []
    @Published var companyInfo: CompanyData?
    @Published var isLoadingHistory = true
    @Published var isLoadingCompany = true
    @Published var companyInfoError: String?
    @Published var timeframePredictions: [TimeframePrediction] = []
    @Published var isLoadingPredictions = false
    @Published var longTermPredictions: [TimeframePrediction] = []
    @Published var isLoadingLongTerm = false

    private let stockService: StockService
    private let accountViewModel: AccountViewModel

    var priceChange: Double {
        guard let first = priceHistory.first?.close,
              let last = priceHistory.last?.close else { return stock.change }
        return last - first
    }

    var priceChangePercent: Double {
        guard let first = priceHistory.first?.close else { return stock.changePercent }
        return (priceChange / first) * 100
    }

    var sharesOwned: Double {
        accountViewModel.sharesOwned(for: stock.symbol)
    }

    init(
        stock: StockData,
        stockService: StockService = .shared,
        accountViewModel: AccountViewModel = .shared
    ) {
        self.stock = stock
        self.stockService = stockService
        self.accountViewModel = accountViewModel
    }

    func loadData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadPriceHistory() }
            group.addTask { await self.loadCompanyInfo() }
            group.addTask { await self.loadPredictions() }
            group.addTask { await self.loadLongTermPredictions() }
        }
    }

    func loadPriceHistory() async {
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            priceHistory = try await stockService.fetchPriceHistory(
                symbol: stock.symbol,
                range: selectedTimeRange.apiRange,
                interval: selectedTimeRange.apiInterval
            )
        } catch {
            priceHistory = []
        }
    }

    func loadCompanyInfo() async {
        isLoadingCompany = true
        companyInfoError = nil
        defer { isLoadingCompany = false }
        do {
            companyInfo = try await stockService.fetchCompanyInfo(symbol: stock.symbol)
        } catch {
            companyInfo = nil
            companyInfoError = error.localizedDescription
            print("Company info fetch failed for \(stock.symbol): \(error)")
        }
    }

    func setTimeRange(_ range: TimeRange) {
        selectedTimeRange = range
    }

    func loadPredictions() async {
        isLoadingPredictions = true
        defer { isLoadingPredictions = false }

        // Each outlook period fetches the history window that best matches
        // its timeframe, then uses that data for analysis.
        struct OutlookConfig {
            let label: String
            let ranges: [(range: String, interval: String, weight: Double)]
            let priceScale: Double
            let horizon: StockPredictionEngine.Horizon
        }

        let outlooks: [OutlookConfig] = [
            OutlookConfig(label: "1 Day", ranges: [
                ("5d", "5m", 0.50),
                ("1mo", "1d", 0.30),
                ("3mo", "1d", 0.20)
            ], priceScale: 1.0 / 30.0, horizon: .shortTerm),
            OutlookConfig(label: "3 Days", ranges: [
                ("5d", "5m", 0.50),
                ("1mo", "1d", 0.30),
                ("3mo", "1d", 0.20)
            ], priceScale: 3.0 / 30.0, horizon: .shortTerm),
            OutlookConfig(label: "1 Month", ranges: [
                ("1mo", "1d", 0.50),
                ("3mo", "1d", 0.30),
                ("6mo", "1d", 0.20)
            ], priceScale: 1.0, horizon: .shortTerm),
            OutlookConfig(label: "6 Months", ranges: [
                ("6mo", "1d", 0.50),
                ("3mo", "1d", 0.30),
                ("1y", "1d", 0.20)
            ], priceScale: 6.0, horizon: .mediumTerm)
        ]

        // Historical average annual equity return (~8%) used as a
        // long-term baseline so predictions aren't purely short-term signals.
        let historicalAnnualReturn = 0.08

        var results: [TimeframePrediction] = []

        for outlook in outlooks {
            var windows: [(label: String, weight: Double, history: [PriceDataPoint])] = []

            for r in outlook.ranges {
                do {
                    let history = try await stockService.fetchPriceHistory(
                        symbol: stock.symbol, range: r.range, interval: r.interval
                    )
                    if history.count >= 10 {
                        windows.append((label: outlook.label, weight: r.weight, history: history))
                    }
                } catch {
                    print("History fetch \(r.range) for \(outlook.label) failed: \(error)")
                }
            }

            guard !windows.isEmpty else { continue }

            var prediction = StockPredictionEngine.aggregatePrediction(
                symbol: stock.symbol,
                name: stock.name,
                currentPrice: stock.price,
                historyWindows: windows,
                horizon: outlook.horizon
            )

            guard !prediction.reasons.contains("Insufficient data for analysis") else { continue }

            // The engine produces a short-term predicted move (e.g. +1.5%).
            // To project over longer timeframes we compound that monthly rate
            // and blend it with a historical baseline so that:
            //   - prices can never go negative (compounding stays > 0)
            //   - long-term predictions reflect both current signals AND
            //     the market's historical growth tendency
            let monthlyRate: Double
            if prediction.currentPrice > 0 {
                monthlyRate = (prediction.predictedPrice / prediction.currentPrice) - 1.0
            } else {
                monthlyRate = 0
            }

            let months = outlook.priceScale  // number of months in this outlook
            let years = months / 12.0

            // Blend the indicator-based rate with historical return.
            // Short timeframes trust indicators more; long timeframes
            // lean toward the historical baseline.
            let indicatorWeight = max(0.2, 1.0 - (years / 15.0))  // e.g. 1mo→0.99, 1yr→0.93, 10yr→0.33
            let historicalMonthly = pow(1.0 + historicalAnnualReturn, 1.0 / 12.0) - 1.0
            let blendedMonthly = monthlyRate * indicatorWeight + historicalMonthly * (1.0 - indicatorWeight)

            let scaledPrice = prediction.currentPrice * pow(1.0 + blendedMonthly, months)

            prediction = StockPrediction(
                symbol: prediction.symbol,
                name: prediction.name,
                sector: prediction.sector,
                currentPrice: prediction.currentPrice,
                predictedPrice: scaledPrice,
                signal: prediction.signal,
                confidence: max(0.15, prediction.confidence * indicatorWeight),
                score: prediction.score,
                reasons: prediction.reasons
            )

            results.append(TimeframePrediction(label: outlook.label, prediction: prediction))
        }

        timeframePredictions = results
    }

    // MARK: - Long-Term Predictions (1–10 Years)

    func loadLongTermPredictions() async {
        isLoadingLongTerm = true
        defer { isLoadingLongTerm = false }

        // Tier 1 – ideal: multi-year weekly bars covering a full market cycle.
        let tier1Ranges: [(range: String, interval: String, weight: Double)] = [
            ("10y", "1wk", 0.50),
            ("5y",  "1wk", 0.35),
            ("2y",  "1wk", 0.15)
        ]
        // Tier 2 – new stocks (<2 years): annual / semi-annual daily bars.
        let tier2Ranges: [(range: String, interval: String, weight: Double)] = [
            ("1y",  "1d", 0.50),
            ("6mo", "1d", 0.35),
            ("3mo", "1d", 0.15)
        ]
        // Tier 3 – very new stocks (<3 months): use whatever daily / intraday bars exist.
        let tier3Ranges: [(range: String, interval: String, weight: Double)] = [
            ("1mo", "1d",  0.60),
            ("5d",  "15m", 0.40)
        ]

        var windows: [(label: String, weight: Double, history: [PriceDataPoint])] = []

        for tierRanges in [tier1Ranges, tier2Ranges, tier3Ranges] {
            if !windows.isEmpty { break }
            for r in tierRanges {
                do {
                    let history = try await stockService.fetchPriceHistory(
                        symbol: stock.symbol, range: r.range, interval: r.interval
                    )
                    if history.count >= 10 {
                        windows.append((label: "Long-Term", weight: r.weight, history: history))
                    }
                } catch {
                    print("Long-term history fetch \(r.range) failed for \(stock.symbol): \(error)")
                }
            }
        }

        guard !windows.isEmpty else { return }

        // ── Historical CAGR ───────────────────────────────────────────────
        // Use the longest available window so the CAGR reflects the real trend.
        // For new stocks with < 3 months of history we fall back to the 8%
        // equity baseline; historyTrust then blends accordingly.
        let longestHistory = windows.max(by: { $0.history.count < $1.history.count })!.history

        let historicalCAGR: Double = {
            guard let firstClose = longestHistory.first?.close,
                  let lastClose  = longestHistory.last?.close,
                  firstClose > 0,
                  let firstDate  = longestHistory.first?.date,
                  let lastDate   = longestHistory.last?.date else { return 0.08 }

            let elapsedYears = lastDate.timeIntervalSince(firstDate) / (365.25 * 24 * 3_600)
            // Need at least ~3 months before we try to annualise returns.
            guard elapsedYears >= 0.25 else { return 0.08 }

            let rawCAGR = pow(lastClose / firstClose, 1.0 / elapsedYears) - 1.0
            // Clamp to sane range: handles penny stocks and 10-bagger ETFs alike.
            // For partial years the annualised figure can be extreme, so apply a
            // tighter cap when the window is short.
            let cap = elapsedYears < 1.0 ? 0.60 : 0.45
            return max(-0.25, min(cap, rawCAGR))
        }()

        // How many years of real history we have (caps at 10 for trust weight).
        let historyYears: Double = {
            guard let f = longestHistory.first?.date,
                  let l = longestHistory.last?.date else { return 0 }
            return min(10, l.timeIntervalSince(f) / (365.25 * 24 * 3_600))
        }()

        // Blend the asset's own CAGR with the generic ~8% equity baseline.
        // Short history → low trust → baseline dominates (correct for new stocks).
        let genericBaseline = 0.08
        let historyTrust    = min(1.0, historyYears / 5.0)   // full trust at 5+ yrs
        let anchoredCAGR    = historicalCAGR * historyTrust
                            + genericBaseline * (1.0 - historyTrust)

        // ── Engine signal pass ────────────────────────────────────────────
        // All indicators fire at longTerm horizon. The score is used only as a
        // ±10%/yr CAGR adjustment — not as the primary rate.
        let basePrediction = StockPredictionEngine.aggregatePrediction(
            symbol: stock.symbol,
            name:   stock.name,
            currentPrice:   stock.price,
            historyWindows: windows,
            horizon:        .longTerm
        )

        // For new stocks the engine may return a neutral / low-confidence signal.
        // We still build projections — they will be anchored to the baseline CAGR
        // with zero technical adjustment and lower confidence.
        let hasEngineSignal = !basePrediction.reasons.contains("Insufficient data for analysis")
                           && !basePrediction.reasons.contains("No data available")

        // Engine score in [-100, +100] → annual CAGR adjustment of ±10%.
        let signalAdjustment = hasEngineSignal ? (basePrediction.score / 100.0) * 0.10 : 0.0

        // ── Per-year projections ──────────────────────────────────────────
        let cagrPct = String(format: "%.1f", anchoredCAGR * 100)
        let histYrLabel = historyYears >= 1.0
            ? "\(Int(historyYears))Y"
            : String(format: "%.0fmo", historyYears * 12)
        let cagrReason = historyYears >= 0.25
            ? "Historical CAGR (\(histYrLabel) data): \(anchoredCAGR >= 0 ? "+" : "")\(cagrPct)%/yr"
            : "Insufficient history — projection uses \(cagrPct)% market baseline"

        var results: [TimeframePrediction] = []

        for year in 1...10 {
            let years = Double(year)

            // Signal influence fades with horizon.  signalWeight: ~0.91 yr1 → ~0.09 yr10.
            let signalWeight  = max(0.05, 1.0 - (years / 11.0))
            let effectiveCAGR = anchoredCAGR + signalAdjustment * signalWeight
            let clampedCAGR   = max(-0.30, min(0.50, effectiveCAGR))
            let scaledPrice   = max(stock.price * 0.01, stock.price * pow(1.0 + clampedCAGR, years))

            // Confidence shrinks with horizon and is further reduced when the
            // engine had too little data to produce a technical signal.
            let baseConfidence   = hasEngineSignal ? basePrediction.confidence : 0.30
            let horizonDecay     = max(0.10, 1.0 - (years / 12.0))
            let yearConfidence   = max(0.10, baseConfidence * horizonDecay)

            let label = year == 1 ? "1 Year" : "\(year) Years"

            var reasons: [String]
            if hasEngineSignal {
                reasons = basePrediction.reasons
                if !reasons.contains(cagrReason) { reasons.insert(cagrReason, at: 1) }
            } else {
                reasons = [
                    cagrReason,
                    "Limited price history — technical indicators unavailable",
                    "Projection anchored to \(String(format: "%.0f", genericBaseline * 100))% annual market baseline"
                ]
            }

            let yearSignal = hasEngineSignal ? basePrediction.signal : .hold
            let yearScore  = hasEngineSignal ? basePrediction.score  : 0.0

            let yearPrediction = StockPrediction(
                symbol:         stock.symbol,
                name:           stock.name,
                sector:         basePrediction.sector,
                currentPrice:   stock.price,
                predictedPrice: scaledPrice,
                signal:         yearSignal,
                confidence:     yearConfidence,
                score:          yearScore,
                reasons:        reasons
            )

            results.append(TimeframePrediction(label: label, prediction: yearPrediction))
        }

        longTermPredictions = results
    }
}
