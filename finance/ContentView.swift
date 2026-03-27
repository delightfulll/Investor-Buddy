//
//  ContentView.swift
//  finance
//
//  Root tab container – MVVM: view only, no business logic.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)
            PortfolioView()
                .tabItem { Label("Portfolio", systemImage: "chart.pie.fill") }
                .tag(1)
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(.blue)
    }
}

#Preview {
    ContentView()
}
