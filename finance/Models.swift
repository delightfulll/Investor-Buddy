//
//  Models.swift
//  finance
//
//  Created by Refactor on 2/12/26
//

import Foundation
import SwiftUI

// MARK: - Trading Type
enum TradingType: String, CaseIterable {
    case cash = "Cash"
    case margin = "Margin"
}

// MARK: - Owned Stock Model
struct OwnedStock: Identifiable, Codable {
    var id = UUID()
    let symbol: String
    let name: String
    var shares: Double
    let averageCost: Double
    var currentPrice: Double
    var previousClose: Double?

    var totalValue: Double { shares * currentPrice }
    var totalReturn: Double { (currentPrice - averageCost) * shares }
    var returnPercentage: Double { ((currentPrice - averageCost) / averageCost) * 100 }

    /// Today's price change per share (current vs previous close)
    var dailyChange: Double {
        guard let prev = previousClose, prev > 0 else { return 0 }
        return currentPrice - prev
    }
    /// Today's total dollar gain/loss across all shares
    var dailyGainLoss: Double { dailyChange * shares }
    /// Today's percentage change
    var dailyChangePercent: Double {
        guard let prev = previousClose, prev > 0 else { return 0 }
        return (dailyChange / prev) * 100
    }
}

// MARK: - Market Movers Models
struct MarketMovers {
    let gainers: [MoverStock]
    let losers: [MoverStock]
}

struct MoverStock: Identifiable {
    let id = UUID()
    let symbol: String
    let name: String
    let price: Double
    let change: Double
    let changePercent: Double
}

// MARK: - Screener Response Models
struct ScreenerResponse: Codable {
    let finance: FinanceData
}

struct FinanceData: Codable {
    let result: [ScreenerResult]?
}

struct ScreenerResult: Codable {
    let quotes: [ScreenerQuote]?
}

struct ScreenerQuote: Codable {
    let symbol: String?
    let shortName: String?
    let longName: String?
    let regularMarketPrice: Double?
    let regularMarketChange: Double?
    let regularMarketChangePercent: Double?
    let marketCap: Int64?
    let averageAnalystRating: String?
    let fiftyTwoWeekChangePercent: Double?
    let regularMarketVolume: Int64?
    let averageDailyVolume3Month: Int64?
}

// MARK: - Discovered Stock for Recommendations
struct DiscoveredStock {
    let symbol: String
    let name: String
    let price: Double
    let sector: String
    let source: String // which screener found it
}

// MARK: - Error Types
enum StockError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case noData
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response from server"
        case .noData: return "No data available"
        case .decodingError: return "Failed to decode response"
        }
    }
}

// MARK: - Data Models
struct StockData: Identifiable, Hashable {
    let id = UUID()
    let symbol: String
    let name: String
    let price: Double
    let change: Double
    let changePercent: Double
    let previousClose: Double
    let open: Double
    let dayHigh: Double
    let dayLow: Double
    let volume: Int
    let marketCap: Int
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(symbol)
    }
    
    static func == (lhs: StockData, rhs: StockData) -> Bool {
        lhs.symbol == rhs.symbol
    }
}

struct PriceDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Int
}

struct CompanyData {
    let symbol: String
    let longName: String
    let sector: String
    let industry: String
    let website: String
    let description: String
    let headquarters: String
    let employees: Int
    let marketCap: String
    let peRatio: Double
    let dividend: Double
    let fiftyTwoWeekHigh: Double
    let fiftyTwoWeekLow: Double
    let averageVolume: Int
    let beta: Double
    let ceo: String
    let founded: String
}

// MARK: - Stock Prediction Models
enum PredictionSignal: String {
    case strongBuy = "Strong Buy"
    case buy = "Buy"
    case hold = "Hold"
    case sell = "Sell"
    case strongSell = "Strong Sell"

    var color: Color {
        switch self {
        case .strongBuy: return .green
        case .buy: return .green.opacity(0.7)
        case .hold: return .orange
        case .sell: return .red.opacity(0.7)
        case .strongSell: return .red
        }
    }

    var icon: String {
        switch self {
        case .strongBuy, .buy: return "arrow.up.right.circle.fill"
        case .hold: return "minus.circle.fill"
        case .sell, .strongSell: return "arrow.down.right.circle.fill"
        }
    }
}

struct StockPrediction: Identifiable {
    let id = UUID()
    let symbol: String
    let name: String
    let sector: String
    let currentPrice: Double
    let predictedPrice: Double
    let signal: PredictionSignal
    let confidence: Double // 0.0 - 1.0
    let score: Double // -100 to +100
    let reasons: [String]

    var predictedChange: Double { predictedPrice - currentPrice }
    var predictedChangePercent: Double {
        currentPrice > 0 ? (predictedChange / currentPrice) * 100 : 0
    }
}

// MARK: - Timeframe Prediction (for stock detail outlook)
struct TimeframePrediction: Identifiable {
    let id = UUID()
    let label: String        // "Next Week", "Next Month", "Next Year"
    let prediction: StockPrediction
}

// MARK: - Metal Quote Model
struct MetalQuote: Identifiable {
    let id = UUID()
    let ticker: String
    let name: String
    let symbol: String
    let price: Double
    let change: Double
    let changePercent: Double
    let unit: String

    var asStockData: StockData {
        StockData(
            symbol: ticker,
            name: name,
            price: price,
            change: change,
            changePercent: changePercent,
            previousClose: price - change,
            open: price,
            dayHigh: price,
            dayLow: price,
            volume: 0,
            marketCap: 0
        )
    }
}

// MARK: - Yahoo Finance API Response Models
struct YahooChartResponse: Codable {
    let chart: ChartData
}

struct ChartData: Codable {
    let result: [ChartResult]?
    let error: ChartError?
}

struct ChartError: Codable {
    let code: String?
    let description: String?
}

struct ChartResult: Codable {
    let meta: ChartMeta?
    let timestamp: [Int]?
    let indicators: Indicators?
}

struct ChartMeta: Codable {
    let symbol: String?
    let shortName: String?
    let longName: String?
    let regularMarketPrice: Double?
    let previousClose: Double?
    let regularMarketOpen: Double?
    let regularMarketDayHigh: Double?
    let regularMarketDayLow: Double?
    let regularMarketVolume: Int?
    let marketCap: Int?
}

struct Indicators: Codable {
    let quote: [Quote]?
}

struct Quote: Codable {
    let open: [Double?]?
    let high: [Double?]?
    let low: [Double?]?
    let close: [Double?]?
    let volume: [Int?]?
}

// MARK: - Yahoo Summary Response Models
struct YahooSummaryResponse: Codable {
    let quoteSummary: QuoteSummary
}

struct QuoteSummary: Codable {
    let result: [SummaryResult]?
}

struct SummaryResult: Codable {
    let assetProfile: AssetProfile?
    let summaryDetail: SummaryDetail?
    let defaultKeyStatistics: KeyStatistics?
}

struct CompanyOfficer: Codable {
    let name: String?
    let title: String?
}

struct AssetProfile: Codable {
    let longName: String?
    let sector: String?
    let industry: String?
    let website: String?
    let longBusinessSummary: String?
    let city: String?
    let state: String?
    let country: String?
    let fullTimeEmployees: Int?
    let companyOfficers: [CompanyOfficer]?
}

struct SummaryDetail: Codable {
    let marketCap: RawValue?
    let trailingPE: RawValue?
    let dividendYield: RawValue?
    let fiftyTwoWeekHigh: RawValue?
    let fiftyTwoWeekLow: RawValue?
    let averageVolume: RawValue?
}

struct KeyStatistics: Codable {
    let beta: RawValue?
}

struct RawValue: Codable {
    let raw: Double?
    let fmt: String?
}

// MARK: - Yahoo Search Response Models
struct YahooSearchResponse: Codable {
    let quotes: [SearchResult]
}

struct SearchResult: Codable, Identifiable {
    var id: String { symbol }
    let symbol: String
    let shortname: String?
    let longname: String?
    let quoteType: String?
    let exchange: String?
    let sector: String?
    let industry: String?
    
    var displayName: String {
        longname ?? shortname ?? symbol
    }
}
