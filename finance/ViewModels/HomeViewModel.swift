//
//  HomeViewModel.swift
//  finance
//
//  MVVM: Home screen – watchlist quotes, market movers, refresh.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var stocks: [StockData] = []
    @Published var topGainers: [MoverStock] = []
    @Published var topLosers: [MoverStock] = []
    @Published var metals: [MetalQuote] = []
    @Published var cryptos: [MetalQuote] = []
    @Published var isLoading = true
    @Published var isLoadingMovers = true
    @Published var isLoadingMetals = true
    @Published var isLoadingCrypto = true
    @Published var lastUpdated: Date?

    private let stockService: StockService
    private let watchlistManager: WatchlistManager
    private let accountViewModel: AccountViewModel

    init(
        stockService: StockService = .shared,
        watchlistManager: WatchlistManager = .shared,
        accountViewModel: AccountViewModel = .shared
    ) {
        self.stockService = stockService
        self.watchlistManager = watchlistManager
        self.accountViewModel = accountViewModel
    }

    func loadData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadStocks() }
            group.addTask { await self.loadMarketMovers() }
            group.addTask { await self.loadMetals() }
            group.addTask { await self.loadCryptos() }
        }
    }

    func loadStocks() async {
        let symbols = watchlistManager.symbols
        guard !symbols.isEmpty else {
            stocks = []
            isLoading = false
            return
        }
        do {
            let fetched = try await stockService.fetchStocks(symbols: symbols)
            stocks = fetched
            lastUpdated = Date()
            for i in accountViewModel.ownedStocks.indices {
                if let data = fetched.first(where: { $0.symbol == accountViewModel.ownedStocks[i].symbol }) {
                    accountViewModel.updateOwnedStockPrice(symbol: data.symbol, price: data.price)
                }
            }
        } catch {
            // keep previous stocks on error
        }
        isLoading = false
    }

    func loadMarketMovers() async {
        do {
            let movers = try await stockService.fetchMarketMovers()
            topGainers = movers.gainers
            topLosers = movers.losers
        } catch {
            // keep previous movers
        }
        isLoadingMovers = false
    }

    func loadMetals() async {
        do {
            let fetched = try await stockService.fetchMetals()
            metals = fetched
        } catch {
            // keep previous metals
        }
        isLoadingMetals = false
    }

    func loadCryptos() async {
        do {
            let fetched = try await stockService.fetchCryptos()
            if !fetched.isEmpty {
                cryptos = fetched
            } else if cryptos.isEmpty {
                // Got an empty response — retry once after a short pause
                // (Yahoo can return empty results under brief rate-limiting).
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let retry = try await stockService.fetchCryptos()
                if !retry.isEmpty { cryptos = retry }
            }
        } catch {
            // Transient network/rate-limit error — keep whatever is already
            // displayed so the section never goes blank mid-session.
            print("Crypto refresh failed, keeping existing data: \(error)")
        }
        isLoadingCrypto = false
    }
}
