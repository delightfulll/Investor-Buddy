//
//  StockService.swift
//  finance
//
//  Created by Vinay Honne on 2/12/26.
//
//  Uses types from Models.swift: StockData, MarketMovers, SearchResult, etc.
//

import Foundation
import SwiftUI

// MARK: - Stock Service
actor StockService {
    static let shared = StockService()
    
    private var cachedCrumb: String?
    private var crumbCookies: [HTTPCookie] = []
    private var crumbFetchDate: Date?
    
    private init() {}
    
    // MARK: - Yahoo Finance Authentication
    // Yahoo Finance v10 quoteSummary requires crumb + cookie auth
    private func ensureCrumb() async throws {
        // Reuse crumb if fetched within the last 30 minutes
        if cachedCrumb != nil, let fetchDate = crumbFetchDate,
           Date().timeIntervalSince(fetchDate) < 1800 {
            return
        }
        
        let cookieStorage = HTTPCookieStorage.shared
        
        // Step 1: Hit fc.yahoo.com to get cookies
        guard let seedURL = URL(string: "https://fc.yahoo.com") else {
            throw StockError.invalidURL
        }
        var seedRequest = URLRequest(url: seedURL)
        seedRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        let (_, seedResponse) = try await URLSession.shared.data(for: seedRequest)
        
        // Store cookies from the response
        if let httpResponse = seedResponse as? HTTPURLResponse,
           let url = httpResponse.url,
           let headerFields = httpResponse.allHeaderFields as? [String: String] {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
            for cookie in cookies {
                cookieStorage.setCookie(cookie)
            }
        }
        
        // Step 2: Fetch the crumb
        guard let crumbURL = URL(string: "https://query2.finance.yahoo.com/v1/test/getcrumb") else {
            throw StockError.invalidURL
        }
        var crumbRequest = URLRequest(url: crumbURL)
        crumbRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        let (crumbData, crumbResponse) = try await URLSession.shared.data(for: crumbRequest)
        
        guard let httpResponse = crumbResponse as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw StockError.invalidResponse
        }
        
        guard let crumb = String(data: crumbData, encoding: .utf8), !crumb.isEmpty else {
            throw StockError.noData
        }
        
        self.cachedCrumb = crumb
        self.crumbFetchDate = Date()
    }
    
    // List of popular stock symbols to track
    static let defaultSymbols = [
        "AAPL", "GOOGL", "MSFT", "AMZN", "TSLA", 
        "NVDA", "META", "NFLX", "AMD", "INTC",
        "DIS", "PYPL", "UBER", "SPOT", "SQ"
    ]
    
    // MARK: - Fetch Multiple Stocks
    func fetchStocks(symbols: [String]) async throws -> [StockData] {
        // Fetch all symbols concurrently for speed
        return await withTaskGroup(of: StockData?.self, returning: [StockData].self) { group in
            for symbol in symbols {
                group.addTask {
                    try? await self.fetchStock(symbol: symbol)
                }
            }
            var stocks: [StockData] = []
            for await result in group {
                if let stock = result {
                    stocks.append(stock)
                }
            }
            return stocks
        }
    }
    
    // MARK: - Fetch Single Stock Quote
    func fetchStock(symbol: String) async throws -> StockData {
        // Using Yahoo Finance API (unofficial but widely used)
        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=1d&range=1d"
        
        guard let url = URL(string: urlString) else {
            throw StockError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw StockError.invalidResponse
        }
        
        let decoded = try JSONDecoder().decode(YahooChartResponse.self, from: data)
        
        guard let result = decoded.chart.result?.first,
              let meta = result.meta else {
            throw StockError.noData
        }
        
        let currentPrice = meta.regularMarketPrice ?? 0
        let previousClose = meta.previousClose ?? currentPrice
        let change = currentPrice - previousClose
        let changePercent = previousClose > 0 ? (change / previousClose) * 100 : 0
        
        return StockData(
            symbol: meta.symbol ?? symbol,
            name: meta.shortName ?? meta.longName ?? symbol,
            price: currentPrice,
            change: change,
            changePercent: changePercent,
            previousClose: previousClose,
            open: meta.regularMarketOpen ?? currentPrice,
            dayHigh: meta.regularMarketDayHigh ?? currentPrice,
            dayLow: meta.regularMarketDayLow ?? currentPrice,
            volume: meta.regularMarketVolume ?? 0,
            marketCap: meta.marketCap ?? 0
        )
    }
    
    // MARK: - Fetch Price History
    func fetchPriceHistory(symbol: String, range: String = "1y", interval: String = "1d") async throws -> [PriceDataPoint] {
        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=\(interval)&range=\(range)"
        
        guard let url = URL(string: urlString) else {
            throw StockError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw StockError.invalidResponse
        }
        
        let decoded = try JSONDecoder().decode(YahooChartResponse.self, from: data)
        
        guard let result = decoded.chart.result?.first,
              let timestamps = result.timestamp,
              let quotes = result.indicators?.quote?.first else {
            throw StockError.noData
        }
        
        var pricePoints: [PriceDataPoint] = []
        
        for (index, timestamp) in timestamps.enumerated() {
            let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
            let close = quotes.close?[index] ?? 0
            let open = quotes.open?[index] ?? close
            let high = quotes.high?[index] ?? close
            let low = quotes.low?[index] ?? close
            let volume = quotes.volume?[index] ?? 0
            
            if close > 0 {
                pricePoints.append(PriceDataPoint(
                    date: date,
                    open: open,
                    high: high,
                    low: low,
                    close: close,
                    volume: volume
                ))
            }
        }
        
        return pricePoints
    }
    
    // MARK: - Fetch Company Info
    func fetchCompanyInfo(symbol: String) async throws -> CompanyData {
        // Ensure we have a valid crumb for authenticated requests
        try await ensureCrumb()
        
        guard let crumb = cachedCrumb else {
            throw StockError.invalidResponse
        }
        
        let encodedCrumb = crumb.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? crumb
        let urlString = "https://query2.finance.yahoo.com/v10/finance/quoteSummary/\(symbol)?modules=assetProfile,summaryDetail,defaultKeyStatistics&crumb=\(encodedCrumb)"
        
        guard let url = URL(string: urlString) else {
            throw StockError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            // If auth failed, clear crumb so it's re-fetched next time
            cachedCrumb = nil
            crumbFetchDate = nil
            throw StockError.invalidResponse
        }
        
        let decoded = try JSONDecoder().decode(YahooSummaryResponse.self, from: data)
        
        guard let result = decoded.quoteSummary.result?.first else {
            throw StockError.noData
        }
        
        let profile = result.assetProfile
        let summary = result.summaryDetail
        let keyStats = result.defaultKeyStatistics
        
        // Extract CEO from company officers (look for CEO or Chief Executive Officer title)
        let ceo = profile?.companyOfficers?.first(where: { officer in
            let title = officer.title?.lowercased() ?? ""
            return title.contains("ceo") || title.contains("chief executive")
        })?.name ?? "N/A"
        
        return CompanyData(
            symbol: symbol,
            longName: profile?.longName ?? symbol,
            sector: profile?.sector ?? "N/A",
            industry: profile?.industry ?? "N/A",
            website: profile?.website ?? "",
            description: profile?.longBusinessSummary ?? "No description available.",
            headquarters: "\(profile?.city ?? ""), \(profile?.state ?? "") \(profile?.country ?? "")",
            employees: profile?.fullTimeEmployees ?? 0,
            marketCap: formatMarketCap(summary?.marketCap?.raw ?? 0),
            peRatio: summary?.trailingPE?.raw ?? 0,
            dividend: summary?.dividendYield?.raw ?? 0,
            fiftyTwoWeekHigh: summary?.fiftyTwoWeekHigh?.raw ?? 0,
            fiftyTwoWeekLow: summary?.fiftyTwoWeekLow?.raw ?? 0,
            averageVolume: Int(summary?.averageVolume?.raw ?? 0),
            beta: keyStats?.beta?.raw ?? 0,
            ceo: ceo,
            founded: "N/A"
        )
    }
    
    private func formatMarketCap(_ value: Double) -> String {
        if value >= 1_000_000_000_000 {
            return String(format: "$%.2fT", value / 1_000_000_000_000)
        } else if value >= 1_000_000_000 {
            return String(format: "$%.2fB", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "$%.2fM", value / 1_000_000)
        } else {
            return String(format: "$%.0f", value)
        }
    }
    
    // MARK: - Search Stocks
    func searchStocks(query: String) async throws -> [SearchResult] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://query1.finance.yahoo.com/v1/finance/search?q=\(encodedQuery)&quotesCount=20&newsCount=0&enableFuzzyQuery=false&quotesQueryId=tss_match_phrase_query"
        
        guard let url = URL(string: urlString) else {
            throw StockError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw StockError.invalidResponse
        }
        
        let decoded = try JSONDecoder().decode(YahooSearchResponse.self, from: data)
        
        // Filter to only show stocks and ETFs (exclude crypto, futures, etc.)
        let validTypes = ["EQUITY", "ETF", "MUTUALFUND"]
        let filtered = decoded.quotes.filter { result in
            validTypes.contains(result.quoteType ?? "")
        }
        
        return filtered
    }
    
    // MARK: - Fetch Market Movers (Top Gainers & Losers)
    func fetchMarketMovers() async throws -> MarketMovers {
        // Fetch top gainers
        let gainersURL = "https://query1.finance.yahoo.com/v1/finance/screener/predefined/saved?scrIds=day_gainers&count=10"
        let gainers = try await fetchScreenerResults(urlString: gainersURL)
        
        // Fetch top losers
        let losersURL = "https://query1.finance.yahoo.com/v1/finance/screener/predefined/saved?scrIds=day_losers&count=10"
        let losers = try await fetchScreenerResults(urlString: losersURL)
        
        return MarketMovers(gainers: gainers, losers: losers)
    }
    
    private func fetchScreenerResults(urlString: String) async throws -> [MoverStock] {
        guard let url = URL(string: urlString) else {
            throw StockError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw StockError.invalidResponse
        }
        
        let decoded = try JSONDecoder().decode(ScreenerResponse.self, from: data)
        
        guard let quotes = decoded.finance.result?.first?.quotes else {
            return []
        }
        
        return quotes.compactMap { quote -> MoverStock? in
            guard let symbol = quote.symbol,
                  let price = quote.regularMarketPrice,
                  let change = quote.regularMarketChange,
                  let changePercent = quote.regularMarketChangePercent else {
                return nil
            }
            
            return MoverStock(
                symbol: symbol,
                name: quote.shortName ?? quote.longName ?? symbol,
                price: price,
                change: change,
                changePercent: changePercent
            )
        }
    }
    
    // MARK: - Discover Stocks by Sector (for Recommendations)
    
    /// All GICS sectors used by Yahoo Finance
    static let allSectors = [
        "Technology", "Energy", "Healthcare", "Financial Services",
        "Consumer Cyclical", "Consumer Defensive", "Industrials",
        "Basic Materials", "Real Estate", "Utilities", "Communication Services"
    ]
    
    /// Discovers top stocks from a specific sector by market cap using the
    /// authenticated custom screener. Returns US equities only.
    func discoverStocks(sector: String, count: Int = 5) async throws -> [DiscoveredStock] {
        try await ensureCrumb()
        
        guard let crumb = cachedCrumb else {
            throw StockError.invalidResponse
        }
        
        let encodedCrumb = crumb.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? crumb
        let urlString = "https://query2.finance.yahoo.com/v1/finance/screener?crumb=\(encodedCrumb)&count=\(count)"
        
        guard let url = URL(string: urlString) else {
            throw StockError.invalidURL
        }
        
        let body: [String: Any] = [
            "size": count,
            "offset": 0,
            "sortField": "intradaymarketcap",
            "sortType": "DESC",
            "quoteType": "EQUITY",
            "query": [
                "operator": "AND",
                "operands": [
                    ["operator": "EQ", "operands": ["region", "us"]],
                    ["operator": "EQ", "operands": ["sector", sector]]
                ]
            ]
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            cachedCrumb = nil
            crumbFetchDate = nil
            throw StockError.invalidResponse
        }
        
        let decoded = try JSONDecoder().decode(ScreenerResponse.self, from: data)
        
        guard let quotes = decoded.finance.result?.first?.quotes else {
            return []
        }
        
        return quotes.compactMap { quote -> DiscoveredStock? in
            guard let symbol = quote.symbol,
                  let price = quote.regularMarketPrice, price > 0 else {
                return nil
            }
            return DiscoveredStock(
                symbol: symbol,
                name: quote.shortName ?? quote.longName ?? symbol,
                price: price,
                sector: sector,
                source: "sector_screener"
            )
        }
    }
    
    // MARK: - Fetch Precious Metals
    func fetchMetals() async throws -> [MetalQuote] {
        let metalSymbols: [(ticker: String, name: String, emoji: String, unit: String)] = [
            ("GC=F", "Gold", "🥇", "/oz"),
            ("SI=F", "Silver", "🥈", "/oz"),
            ("PL=F", "Platinum", "⚪", "/oz")
        ]

        return await withTaskGroup(of: MetalQuote?.self, returning: [MetalQuote].self) { group in
            for metal in metalSymbols {
                group.addTask {
                    guard let stock = try? await self.fetchStock(symbol: metal.ticker) else { return nil }
                    return MetalQuote(
                        ticker: metal.ticker,
                        name: metal.name,
                        symbol: metal.emoji,
                        price: stock.price,
                        change: stock.change,
                        changePercent: stock.changePercent,
                        unit: metal.unit
                    )
                }
            }
            var quotes: [MetalQuote] = []
            for await result in group {
                if let quote = result { quotes.append(quote) }
            }
            return quotes
        }
    }
    
    /// Discovers today's most relevant stocks using Yahoo Finance's live daily
    /// screeners. Returns a deduplicated set of stocks that are actually moving
    /// or notable in today's market — the count varies based on real market data.
    func discoverTodaysMarket() async throws -> [DiscoveredStock] {
        let screeners = [
            ("day_gainers", "Top Gainer"),
            ("day_losers", "Top Loser"),
            ("most_actives", "Most Active"),
            ("undervalued_large_caps", "Undervalued"),
            ("undervalued_growth_stocks", "Growth"),
            ("aggressive_small_caps", "Small Cap"),
            ("small_cap_gainers", "Small Cap Gainer")
        ]
        
        var allStocks: [DiscoveredStock] = []
        var seenSymbols: Set<String> = []
        
        for (scrId, category) in screeners {
            let urlString = "https://query1.finance.yahoo.com/v1/finance/screener/predefined/saved?scrIds=\(scrId)&count=25"
            guard let url = URL(string: urlString) else { continue }
            
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else { continue }
                
                let decoded = try JSONDecoder().decode(ScreenerResponse.self, from: data)
                guard let quotes = decoded.finance.result?.first?.quotes else { continue }
                
                for quote in quotes {
                    guard let symbol = quote.symbol,
                          let price = quote.regularMarketPrice, price > 0,
                          !seenSymbols.contains(symbol) else { continue }
                    seenSymbols.insert(symbol)
                    allStocks.append(DiscoveredStock(
                        symbol: symbol,
                        name: quote.shortName ?? quote.longName ?? symbol,
                        price: price,
                        sector: category,
                        source: scrId
                    ))
                }
            } catch {
                print("Screener \(scrId) failed: \(error)")
            }
        }
        
        return allStocks
    }
}
