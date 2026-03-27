//
//  WatchlistManager.swift
//  finance
//
//  Created by Refactor on 2/12/26
//

import Foundation
import SwiftUI
import Combine

// MARK: - Watchlist Manager
@MainActor
class WatchlistManager: ObservableObject {
    static let shared = WatchlistManager()
    
    @Published var symbols: [String] = []
    
    private let userDefaultsKey = "userWatchlist"
    
    private init() {
        loadWatchlist()
    }
    
    func loadWatchlist() {
        if let saved = UserDefaults.standard.stringArray(forKey: userDefaultsKey) {
            symbols = saved
        } else {
            // Start with a few default stocks if first launch
            symbols = ["AAPL", "GOOGL", "MSFT"]
            saveWatchlist()
        }
    }
    
    func saveWatchlist() {
        UserDefaults.standard.set(symbols, forKey: userDefaultsKey)
    }
    
    func addSymbol(_ symbol: String) {
        let upperSymbol = symbol.uppercased()
        if !symbols.contains(upperSymbol) {
            symbols.append(upperSymbol)
            saveWatchlist()
        }
    }
    
    func removeSymbol(_ symbol: String) {
        symbols.removeAll { $0 == symbol.uppercased() }
        saveWatchlist()
    }
    
    func isInWatchlist(_ symbol: String) -> Bool {
        symbols.contains(symbol.uppercased())
    }
    
    func moveSymbol(from source: IndexSet, to destination: Int) {
        symbols.move(fromOffsets: source, toOffset: destination)
        saveWatchlist()
    }
}

