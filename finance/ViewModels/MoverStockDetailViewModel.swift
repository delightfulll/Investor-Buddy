//
//  MoverStockDetailViewModel.swift
//  finance
//
//  MVVM: Mover stock detail – load full stock by symbol, then show detail.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class MoverStockDetailViewModel: ObservableObject {
    let moverStock: MoverStock
    @Published var stockData: StockData?
    @Published var isLoading = true
    @Published var errorMessage: String?

    private let stockService: StockService

    init(moverStock: MoverStock, stockService: StockService = .shared) {
        self.moverStock = moverStock
        self.stockService = stockService
    }

    func loadStock() async {
        isLoading = true
        errorMessage = nil
        do {
            stockData = try await stockService.fetchStock(symbol: moverStock.symbol)
        } catch {
            errorMessage = "Failed to load stock data"
        }
        isLoading = false
    }
}
