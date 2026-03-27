//
//  StocksViewModel.swift
//  finance
//
//  Created by Refactor on 2/12/26
//

import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class StocksViewModel {
    private(set) var stocks: [StockData] = []
    private(set) var movers: MarketMovers? = nil
    private(set) var isLoading: Bool = false
    var errorMessage: String? = nil
    
    private let service: StockService
    
    init(service: StockService = StockService.shared) {
        self.service = service
    }
    
    func loadInitial() async {
        isLoading = true
        errorMessage = nil
        await withTaskCancellationHandler {
            Task { @MainActor in
                isLoading = false
            }
        } operation: {
            do {
                let symbols = await WatchlistManager.shared.symbols
                let fetched = try await service.fetchStocks(symbols: symbols)
                await MainActor.run {
                    stocks = fetched.sorted { $0.symbol < $1.symbol }
                }
                let moversResult = try? await service.fetchMarketMovers()
                await MainActor.run {
                    movers = moversResult
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    func refreshStocks() async {
        do {
            let fetched = try await service.fetchStocks(symbols: await WatchlistManager.shared.symbols)
            stocks = fetched.sorted { $0.symbol < $1.symbol }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func search(_ query: String) async -> [SearchResult] {
        do {
            return try await service.searchStocks(query: query)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }
}

