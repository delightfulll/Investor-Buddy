//
//  SearchView.swift
//  finance
//
//  MVVM: Search screen – binds to SearchViewModel.
//

import SwiftUI

struct SearchView: View {
    @StateObject private var searchVM = SearchViewModel()
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var addedSymbol: String?
    @State private var showAddedConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search stocks by name or symbol...", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchVM.searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if searchVM.isSearching {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding()

                Divider()

                if searchText.isEmpty {
                    watchlistManagementView
                } else if searchVM.searchResults.isEmpty && !searchVM.isSearching {
                    noResultsView
                } else {
                    searchResultsView
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Search")
            .overlay(alignment: .bottom) {
                if showAddedConfirmation, let symbol = addedSymbol {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                        Text("\(symbol) added to Watchlist")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.green)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    
                    //dissapears here
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation(.easeInOut) {
                                showAddedConfirmation = false
                                addedSymbol = nil
                            }
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showAddedConfirmation)
        }
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            guard !newValue.isEmpty else {
                searchVM.searchResults = []
                return
            }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await searchVM.search(query: newValue)
            }
        }
    }

    private var watchlistManagementView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if searchVM.watchlistSymbols.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                    Text("Search for stocks")
                        .font(.headline)
                    Text("Find stocks by name or ticker symbol and add them to your watchlist")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Your Watchlist")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top)

                List {
                    ForEach(searchVM.watchlistSymbols, id: \.self) { symbol in
                        HStack {
                            Text(symbol)
                                .font(.headline)
                            Spacer()
                            Button {
                                searchVM.removeFromWatchlist(symbol)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .onMove { source, destination in
                        searchVM.moveWatchlist(from: source, to: destination)
                    }
                    .onDelete { indexSet in
                        searchVM.removeWatchlist(at: indexSet)
                    }
                }
                .listStyle(.plain)
                .environment(\.editMode, .constant(.active))
            }
        }
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No results found")
                .font(.headline)
            Text("Try searching for a company name or stock symbol")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchResultsView: some View {
        List(searchVM.searchResults) { result in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.symbol)
                        .font(.headline)
                    Text(result.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let exchange = result.exchange {
                        Text(exchange)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if searchVM.isInWatchlist(result.symbol) {
                    Button {
                        searchVM.removeFromWatchlist(result.symbol)
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    }
                } else {
                    Button {
                        searchVM.addToWatchlist(result.symbol)
                        addedSymbol = result.symbol
                        showAddedConfirmation = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .listStyle(.plain)
    }
}
