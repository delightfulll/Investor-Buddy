//
//  PortfolioViewModel.swift
//  finance
//
//  MVVM: Portfolio screen – summary and holdings from account + watchlist data.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class PortfolioViewModel: ObservableObject {
    @Published var watchlistStocks: [StockData] = []

    private let accountViewModel: AccountViewModel
    private let stockService: StockService
    private let watchlistManager: WatchlistManager

    var portfolioValue: Double { accountViewModel.portfolioValue }
    var totalReturn: Double { accountViewModel.totalReturn }
    var currentBuyingPower: Double { accountViewModel.currentBuyingPower }
    var ownedStocks: [OwnedStock] { accountViewModel.ownedStocks }

    init(
        accountViewModel: AccountViewModel = .shared,
        stockService: StockService = .shared,
        watchlistManager: WatchlistManager = .shared
    ) {
        self.accountViewModel = accountViewModel
        self.stockService = stockService
        self.watchlistManager = watchlistManager
    }

    func loadWatchlistStocks() async {
        let symbols = watchlistManager.symbols
        guard !symbols.isEmpty else {
            watchlistStocks = []
            return
        }
        do {
            let fetched = try await stockService.fetchStocks(symbols: symbols)
            // Only replace the list when we actually got data back.
            if !fetched.isEmpty {
                watchlistStocks = fetched
            }
        } catch {
            // Network error (e.g. rate-limiting from concurrent requests) —
            // keep the existing list visible rather than blanking the screen.
            print("Watchlist refresh failed, keeping existing data: \(error)")
        }
    }
}
