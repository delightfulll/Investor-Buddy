//
//  TransferSheetView.swift
//  finance
//
//  MVVM: Transfer sheet – binds to TransferSheetViewModel.
//

import SwiftUI

struct TransferSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = TransferSheetViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("From") {
                    Picker("From Account", selection: $vm.fromAccount) {
                        ForEach(TransferAccount.allCases, id: \.self) { account in
                            HStack {
                                Text(account.rawValue)
                                Spacer()
                                Text(vm.balance(for: account), format: .currency(code: "USD"))
                                    .foregroundStyle(.secondary)
                            }
                            .tag(account)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("To") {
                    Picker("To Account", selection: $vm.toAccount) {
                        ForEach(TransferAccount.allCases.filter { $0 != vm.fromAccount }, id: \.self) { account in
                            HStack {
                                Text(account.rawValue)
                                Spacer()
                                Text(vm.balance(for: account), format: .currency(code: "USD"))
                                    .foregroundStyle(.secondary)
                            }
                            .tag(account)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Amount") {
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $vm.amount)
                            .keyboardType(.decimalPad)
                    }
                }
                Section {
                    Button {
                        if vm.executeTransfer() {
                            dismiss()
                        }
                    } label: {
                        Text("Transfer")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .disabled(vm.amount.isEmpty)
                }
            }
            .navigationTitle("Transfer Money")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Transfer Error", isPresented: $vm.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(vm.errorMessage)
            }
            .onChange(of: vm.fromAccount) { _, _ in
                vm.fixToAccountIfNeeded()
            }
        }
    }
}
