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
            watchlistStocks = try await stockService.fetchStocks(symbols: symbols)
        } catch {
            watchlistStocks = []
        }
    }
}
