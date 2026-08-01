import SwiftUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedTab: AppTab = .dashboard
    @State private var selectedSidebarTab: AppTab? = .dashboard
    @State private var columnVisibility = NavigationSplitViewVisibility.detailOnly

    var body: some View {
        if sizeClass == .compact {
            iPhoneTabView
        } else {
            iPadSplitView
        }
    }

    private var iPhoneTabView: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }
                .tag(AppTab.dashboard)
            ExpenseListView()
                .tabItem { Label("Expenses", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.expenses)
            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray.fill") }
                .tag(AppTab.inbox)
            BudgetsView()
                .tabItem { Label("Budgets", systemImage: "chart.pie.fill") }
                .tag(AppTab.budgets)
            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis") }
                .tag(AppTab.more)
        }
    }

    private var iPadSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(AppTab.allCases, id: \.self, selection: $selectedSidebarTab) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationTitle("CharmFi")
            .onChange(of: selectedSidebarTab) {
                columnVisibility = .detailOnly
            }
        } detail: {
            switch selectedSidebarTab ?? .dashboard {
            case .dashboard: DashboardView()
            case .expenses: ExpenseListView()
            case .inbox: InboxView()
            case .budgets: BudgetsView()
            case .more: MoreView()
            }
        }
        // detailOnly + prominentDetail = sidebar overlays as a backdrop in portrait,
        // slides out as a panel in landscape
        .navigationSplitViewStyle(.prominentDetail)
    }
}

enum AppTab: String, CaseIterable {
    case dashboard, expenses, inbox, budgets, more

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .expenses: "Expenses"
        case .inbox: "Inbox"
        case .budgets: "Budgets"
        case .more: "More"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "chart.bar.fill"
        case .expenses: "list.bullet.rectangle"
        case .inbox: "tray.fill"
        case .budgets: "chart.pie.fill"
        case .more: "ellipsis"
        }
    }
}
