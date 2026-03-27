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
            ], priceScale: 6.0, horizon: .mediumTerm),
            OutlookConfig(label: "1 Year", ranges: [
                ("1y", "1d", 0.50),
                ("6mo", "1d", 0.25),
                ("5y", "1wk", 0.25)
            ], priceScale: 12.0, horizon: .mediumTerm),
            OutlookConfig(label: "10 Years", ranges: [
                ("10y", "1wk", 0.50),
                ("5y", "1wk", 0.30),
                ("1y", "1d", 0.20)
            ], priceScale: 120.0, horizon: .longTerm)
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
                    if history.count >= 20 {
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
}
