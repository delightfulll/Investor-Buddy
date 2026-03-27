//
//  MoverStockDetailView.swift
//  finance
//
//  MVVM: Mover stock detail – loads full stock then shows StockDetailView.
//

import SwiftUI

struct MoverStockDetailView: View {
    let moverStock: MoverStock
    @StateObject private var vm: MoverStockDetailViewModel

    init(moverStock: MoverStock) {
        self.moverStock = moverStock
        _vm = StateObject(wrappedValue: MoverStockDetailViewModel(moverStock: moverStock))
    }

    var body: some View {
        Group {
            if vm.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading \(moverStock.symbol)...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(error)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await vm.loadStock() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let stock = vm.stockData {
                StockDetailView(stock: stock)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(moverStock.symbol)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await vm.loadStock()
        }
    }
}
