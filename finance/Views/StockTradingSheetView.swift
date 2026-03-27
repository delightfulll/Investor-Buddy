//
//  StockTradingSheetView.swift
//  finance
//
//  MVVM: Trade sheet – binds to StockTradingSheetViewModel.
//

import SwiftUI

struct StockTradingSheetView: View {
    let stock: StockData

    var body: some View {
        StockTradingSheetContent(stock: stock)
    }
}

private struct StockTradingSheetContent: View {
    @Environment(\.dismiss) private var dismiss
    let stock: StockData
    @StateObject private var vm: StockTradingSheetViewModel
    @StateObject private var accountVM = AccountViewModel.shared

    init(stock: StockData) {
        self.stock = stock
        _vm = StateObject(wrappedValue: StockTradingSheetViewModel(stock: stock))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stockHeader
                orderTypePicker
                ScrollView {
                    VStack(spacing: 24) {
                        priceDisplay
                        sharesInput
                        orderSummary
                    }
                    .padding()
                }
                actionButton
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.semibold)
                    }
                }
            }
            .alert("Order Confirmation", isPresented: $vm.showConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button(vm.orderType == .buy ? "Buy" : "Sell") {
                    vm.executeOrder()
                    dismiss()
                }
            } message: {
                if vm.orderType == .buy {
                    Text("Buy \(vm.shares) shares of \(stock.symbol) for \(vm.estimatedCost, format: .currency(code: "USD"))?")
                } else {
                    Text("Sell \(vm.shares) shares of \(stock.symbol) for \(vm.estimatedCost, format: .currency(code: "USD"))?")
                }
            }
            .alert("Order Error", isPresented: $vm.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(vm.errorMessage)
            }
        }
    }

    private var stockHeader: some View {
        VStack(spacing: 8) {
            Text(stock.symbol)
                .font(.title)
                .fontWeight(.bold)
            Text(stock.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if accountVM.tradingType == .margin {
                Text("Margin Trading")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    private var orderTypePicker: some View {
        Picker("Order Type", selection: $vm.orderType) {
            ForEach(StockTradingSheetViewModel.OrderType.allCases, id: \.self) { type in
                Text(type.rawValue).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .padding()
        .background(Color.white)
    }

    private var priceDisplay: some View {
        VStack(spacing: 8) {
            Text("Market Price")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(stock.price, format: .currency(code: "USD"))
                .font(.system(size: 44, weight: .bold))
            HStack(spacing: 4) {
                Image(systemName: stock.change >= 0 ? "arrow.up.right" : "arrow.down.right")
                Text(String(format: "%.2f", abs(stock.change)))
                Text(String(format: "(%.2f%%)", abs(stock.changePercent)))
            }
            .font(.subheadline)
            .foregroundStyle(stock.change >= 0 ? .green : .red)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var sharesInput: some View {
        VStack(spacing: 16) {
            Text("Number of Shares")
                .font(.headline)
            HStack {
                Button {
                    if let current = Int(vm.shares), current > 1 {
                        vm.shares = String(current - 1)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title)
                        .foregroundStyle(.blue)
                }
                TextField("0", text: $vm.shares)
                    .font(.system(size: 48, weight: .bold))
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .frame(width: 120)
                Button {
                    if let current = Int(vm.shares) {
                        vm.shares = String(current + 1)
                    } else {
                        vm.shares = "1"
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                        .foregroundStyle(.blue)
                }
            }
            HStack(spacing: 12) {
                ForEach([1, 5, 10, 25], id: \.self) { amount in
                    Button {
                        vm.shares = String(amount)
                    } label: {
                        Text("\(amount)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                            .frame(width: 50, height: 36)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var orderSummary: some View {
        VStack(spacing: 12) {
            HStack {
                Text(vm.orderType == .buy ? "Buying Power" : "Shares Owned")
                    .foregroundStyle(.secondary)
                Spacer()
                if vm.orderType == .buy {
                    VStack(alignment: .trailing) {
                        Text(accountVM.currentBuyingPower, format: .currency(code: "USD"))
                            .fontWeight(.semibold)
                        if accountVM.tradingType == .margin {
                            Text("(Margin)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                } else {
                    Text("\(String(format: "%.2f", vm.sharesOwned)) shares")
                        .fontWeight(.semibold)
                }
            }
            Divider()
            HStack {
                Text("Estimated \(vm.orderType == .buy ? "Cost" : "Credit")")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(vm.estimatedCost, format: .currency(code: "USD"))
                    .fontWeight(.semibold)
                    .foregroundColor(vm.orderType == .buy ? .primary : .green)
            }
        }
        .padding()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var actionButton: some View {
        Button {
            vm.validateAndConfirm()
        } label: {
            Text(vm.orderType == .buy ? "Review Buy Order" : "Review Sell Order")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(vm.orderType == .buy ? Color.green : Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(vm.shares.isEmpty || (Double(vm.shares) ?? 0) <= 0)
        .padding()
        .background(Color.white)
    }
}
