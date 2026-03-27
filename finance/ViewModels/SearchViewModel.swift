//
//  SearchViewModel.swift
//  finance
//
//  MVVM: Search screen – query, results, watchlist add/remove.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching = false

    private let stockService: StockService
    private let watchlistManager: WatchlistManager

    var watchlistSymbols: [String] { watchlistManager.symbols }

    init(
        stockService: StockService = .shared,
        watchlistManager: WatchlistManager = .shared
    ) {
        self.stockService = stockService
        self.watchlistManager = watchlistManager
    }

    func search(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            searchResults = try await stockService.searchStocks(query: query)
        } catch {
            searchResults = []
        }
    }

    func addToWatchlist(_ symbol: String) {
        watchlistManager.addSymbol(symbol)
    }

    func removeFromWatchlist(_ symbol: String) {
        watchlistManager.removeSymbol(symbol)
    }

    func isInWatchlist(_ symbol: String) -> Bool {
        watchlistManager.isInWatchlist(symbol)
    }

    func moveWatchlist(from source: IndexSet, to destination: Int) {
        watchlistManager.moveSymbol(from: source, to: destination)
    }

    func removeWatchlist(at indexSet: IndexSet) {
        for index in indexSet where index < watchlistManager.symbols.count {
            watchlistManager.removeSymbol(watchlistManager.symbols[index])
        }
    }
}
