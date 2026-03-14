//
//  ContentView.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-12.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("selectedTab") private var selectedTab: Int = 0
    @State private var showingAddTransaction = false
    @Query(filter: #Predicate<Subscription> { $0.isActive })
    private var activeSubscriptions: [Subscription]

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("tab.home", systemImage: "house.fill") }
                .tag(0)

            ProjectionView()
                .tabItem { Label("tab.projection", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(1)

            // Tab + : jamais affiché — intercepté par onChange pour ouvrir la sheet
            Color.clear
                .tabItem { Label("tab.add", systemImage: "plus.circle.fill") }
                .tag(2)

            SubscriptionsView()
                .tabItem { Label("tab.subscriptions", systemImage: "rectangle.stack.fill") }
                .tag(3)

            ObjectifsView()
                .tabItem { Label("tab.goals", systemImage: "target") }
                .tag(4)
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == 2 {
                selectedTab = oldValue
                showingAddTransaction = true
            }
        }
        .sheet(isPresented: $showingAddTransaction) {
            AddTransactionView()
        }
        .task {
            await NotificationManager.shared.rescheduleAll(subscriptions: activeSubscriptions)
        }
    }
}

// MARK: - Placeholders

struct AccueilView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                String(localized: "tab.home"),
                systemImage: "house.fill",
                description: Text("placeholder.coming_soon")
            )
            .navigationTitle(String(localized: "tab.home"))
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct ObjectifsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                String(localized: "tab.goals"),
                systemImage: "target",
                description: Text("placeholder.coming_soon")
            )
            .navigationTitle(String(localized: "tab.goals"))
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    ContentView()
}
