//
//  StockRecommendationViewModel.swift
//  finance
//
//  MVVM: Dynamically discovers stocks from all market sectors
//  via Yahoo Finance screeners, runs the prediction engine,
//  and surfaces top recommendations.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class StockRecommendationViewModel: ObservableObject {
    @Published var recommendations: [StockPrediction] = []
    @Published var isLoading = false
    @Published var hasLoaded = false
    @Published var loadingStatus: String = ""
    @Published var sectorsLoaded: Int = 0

    private let stockService: StockService

    init(stockService: StockService = .shared) {
        self.stockService = stockService
    }

    func loadRecommendations() async {
        guard !isLoading else { return }
        isLoading = true
        loadingStatus = "Scanning today's market..."
        sectorsLoaded = 0
        defer {
            isLoading = false
            hasLoaded = true
            loadingStatus = ""
        }

        // Pull stocks from today's live market screeners (gainers, losers,
        // most active, undervalued, growth, small caps). The count is
        // determined entirely by what the API returns for today.
        var discoveredStocks: [DiscoveredStock] = []
        do {
            discoveredStocks = try await stockService.discoverTodaysMarket()
        } catch {
            print("Market discovery failed: \(error)")
        }

        guard !discoveredStocks.isEmpty else {
            loadingStatus = "No stocks found"
            return
        }

        let totalCount = discoveredStocks.count
        loadingStatus = "Analyzing today's market (\(totalCount) stocks found)..."

        var predictions: [StockPrediction] = []
        var analyzed = 0

        for stock in discoveredStocks {
            // Fetch multiple history windows for richer analysis
            let ranges: [(label: String, range: String, interval: String, weight: Double)] = [
                ("1M", "1mo", "1d", 0.20),
                ("3M", "3mo", "1d", 0.30),
                ("1Y", "1y", "1d", 0.25),
                ("5Y", "5y", "1wk", 0.15),
                ("10Y", "10y", "1wk", 0.10)
            ]

            var windows: [(label: String, weight: Double, history: [PriceDataPoint])] = []
            for r in ranges {
                do {
                    let history = try await stockService.fetchPriceHistory(
                        symbol: stock.symbol, range: r.range, interval: r.interval
                    )
                    if !history.isEmpty {
                        windows.append((label: r.label, weight: r.weight, history: history))
                    }
                } catch {
                    // Skip failed ranges, continue with available data
                }
            }

            let prediction: StockPrediction
            if windows.count >= 2 {
                prediction = StockPredictionEngine.aggregatePrediction(
                    symbol: stock.symbol,
                    name: stock.name,
                    sector: stock.sector,
                    currentPrice: stock.price,
                    historyWindows: windows
                )
            } else if let singleWindow = windows.first {
                prediction = StockPredictionEngine.predict(
                    symbol: stock.symbol,
                    name: stock.name,
                    sector: stock.sector,
                    currentPrice: stock.price,
                    priceHistory: singleWindow.history
                )
            } else {
                analyzed += 1
                continue
            }

            predictions.append(prediction)

            analyzed += 1
            loadingStatus = "Analyzed \(analyzed) of \(totalCount)..."

            // Update recommendations progressively every 5 stocks
            if analyzed % 5 == 0 {
                recommendations = predictions.sorted { $0.score > $1.score }
            }
        }

        // Final sort
        recommendations = predictions.sorted { $0.score > $1.score }
    }
}
