//
//  SettingsView.swift
//  finance
//
//  MVVM: Settings screen – binds to AccountViewModel for trading type.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var accountVM = AccountViewModel.shared
    @State private var showResetAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.title)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text("Vinay Honne")
                                .font(.headline)
                            Text("Personal Account")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Trading") {
                    HStack {
                        Text("Default Trading Type")
                        Spacer()
                        Picker("", selection: $accountVM.tradingType) {
                            ForEach(TradingType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }
                    NavigationLink {
                        marginSettingsView
                    } label: {
                        HStack {
                            Text("Margin Settings")
                            Spacer()
                            Text(accountVM.tradingType == .margin ? "Enabled" : "Disabled")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Notifications") {
                    Toggle("Price Alerts", isOn: .constant(true))
                    Toggle("Market News", isOn: .constant(false))
                    Toggle("Portfolio Updates", isOn: .constant(true))
                }

                Section("Security") {
                    NavigationLink("Face ID / Touch ID") {
                        Text("Biometric settings would go here")
                            .navigationTitle("Security")
                    }
                    NavigationLink("Change PIN") {
                        Text("PIN settings would go here")
                            .navigationTitle("Change PIN")
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink("Terms of Service") {
                        Text("Terms of Service would go here")
                            .navigationTitle("Terms of Service")
                    }
                    NavigationLink("Privacy Policy") {
                        Text("Privacy Policy would go here")
                            .navigationTitle("Privacy Policy")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showResetAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Reset All Data")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Reset All Data?", isPresented: $showResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    // Reset logic would go here
                }
            } message: {
                Text("This will reset all your portfolio data and settings. This action cannot be undone.")
            }
        }
    }

    private var marginSettingsView: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Margin Trading")
                        .font(.headline)
                    Text("Margin trading allows you to borrow money to invest, increasing your buying power but also your risk.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section("Current Status") {
                HStack {
                    Text("Margin Buying Power")
                    Spacer()
                    Text(accountVM.marginBuyingPower, format: .currency(code: "USD"))
                        .fontWeight(.semibold)
                }
                HStack {
                    Text("Cash Balance")
                    Spacer()
                    Text(accountVM.buyingPower, format: .currency(code: "USD"))
                }
                HStack {
                    Text("Leverage")
                    Spacer()
                    Text("2x")
                        .foregroundStyle(.orange)
                        .fontWeight(.semibold)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Risk Warning")
                            .fontWeight(.semibold)
                    }
                    Text("Trading on margin carries significant risk. You can lose more than your initial investment. Only trade with money you can afford to lose.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Margin Settings")
    }
}
