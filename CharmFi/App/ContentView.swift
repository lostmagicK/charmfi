import SwiftUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedTab: AppTab = .dashboard
    @State private var columnVisibility = NavigationSplitViewVisibility.detailOnly
    @State private var showMenuSheet = false
    // Owned here, above the orientation-driven layout switch below, so rotating the device
    // (which swaps the whole tab/split subtree) doesn't blow away whatever page was opened
    // from the Menu grid.
    @State private var menuDestination: MenuDestination?
    // TabView keeps its own copy of the selection internally. If the binding never lets it
    // reach the value the user tapped, it stays desynced and re-fires the setter on every
    // re-render — so `.more` has to land here for real and be reverted, rather than being
    // filtered out in a computed binding. `selectedTab` is the value that actually persists.
    @State private var tabBarSelection: AppTab = .dashboard
    // Latched rather than read straight off the geometry: see the guards in the handlers below.
    @State private var useSplitLayout = false
    @State private var didInitialLayout = false

    var body: some View {
        ZStack {
            Group {
                if useSplitLayout { iPadSplitView } else { tabLayout }
            }
            .background(orientationProbe)

            if let destination = menuDestination {
                // Layered in rather than presented as a sheet/fullScreenCover: a cover can't
                // come up while the menu sheet is still on screen, and a presentation gets
                // torn down when the presenting tree changes on rotation.
                menuPage(destination)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .animation(.snappy(duration: 0.25), value: menuDestination)
        .sheet(isPresented: $showMenuSheet) {
            MenuView { destination in
                // Close the sheet and open the page in the same update.
                showMenuSheet = false
                menuDestination = destination
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Layout

    /// Decides tab-vs-split purely from the window's shape, and does it in a zero-size backdrop
    /// so nothing user-visible depends on the reading.
    ///
    /// `.ignoresSafeArea(.keyboard)` is the point of it: keyboard avoidance shortens the view
    /// while the keyboard is up, and on iPad portrait that alone was enough to make it measure
    /// wider than tall. The layout would flip to split the instant you tapped a text field,
    /// rebuilding the whole tree, dropping first responder and dismissing the keyboard — which
    /// restored the height, flipped it back, and left the field unfocused.
    private var orientationProbe: some View {
        GeometryReader { proxy in
            let wantsSplit = sizeClass != .compact && proxy.size.width >= proxy.size.height

            Color.clear
                .onChange(of: wantsSplit, initial: true) { _, newValue in
                    // Hold the layout steady while a menu page covers the screen. Swapping
                    // TabView for NavigationSplitView rebuilds the entire tree underneath,
                    // which is what used to kick you out of an open page on rotation.
                    guard menuDestination == nil else { return }
                    // First pass runs before anything is on screen — latch it outright.
                    guard didInitialLayout else {
                        didInitialLayout = true
                        useSplitLayout = newValue
                        return
                    }
                    guard newValue != useSplitLayout else { return }
                    // Latching the value moved the swap out of the rotation's own animation
                    // transaction, so it has to be re-animated here or the layout hard-cuts
                    // instead of rearranging.
                    withAnimation(.smooth(duration: 0.35)) { useSplitLayout = newValue }
                }
                .onChange(of: menuDestination) { _, newValue in
                    // Catch up to the current orientation once the page is closed again.
                    if newValue == nil { useSplitLayout = wantsSplit }
                }
        }
        .ignoresSafeArea(.keyboard)
    }

    // MARK: - Menu page

    private func menuPage(_ destination: MenuDestination) -> some View {
        NavigationStack {
            destination.destinationView
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button { menuDestination = nil } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    // MARK: - Selection

    /// `.more` and `.ai` are buttons, not destinations: they open the menu / the AI page and
    /// leave the real selection untouched. Shared by both layouts so rotating never changes
    /// the tab.
    private func select(_ tab: AppTab) {
        switch tab {
        case .more: showMenuSheet = true
        case .ai: menuDestination = .ai
        default: selectedTab = tab
        }
    }

    private var sidebarSelection: Binding<AppTab?> {
        Binding(get: { selectedTab }, set: { newValue in
            if let newValue { select(newValue) }
        })
    }

    // MARK: - Compact layout

    @ViewBuilder
    private var tabLayout: some View {
        styledTabView
            .onAppear { tabBarSelection = selectedTab }
            .onChange(of: selectedTab) { _, newValue in
                // Keep in step when the selection was made in the other layout.
                if newValue != tabBarSelection { tabBarSelection = newValue }
            }
            .onChange(of: tabBarSelection) { oldValue, newValue in
                guard newValue == .more || newValue == .ai else {
                    selectedTab = newValue
                    return
                }
                // Bounce back off the button tabs, then open the sheet / page.
                tabBarSelection = oldValue
                select(newValue)
            }
    }

    @ViewBuilder
    private var styledTabView: some View {
        if sizeClass == .regular {
            // iPadOS renders the native bar as a floating strip at the top with no supported
            // way to reposition it, so hide it and inset our own pill along the bottom. The
            // TabView itself stays — it keeps every tab's content alive between switches.
            baseTabView
                .safeAreaInset(edge: .bottom) {
                    FloatingTabBar(selection: selectedTab, onSelect: select)
                }
        } else if #available(iOS 18.0, *) {
            // Force the classic bottom tab bar; without this, iPadOS 18+ renders
            // TabView as a floating top bar even in the compact/portrait branch.
            baseTabView.tabViewStyle(.tabBarOnly)
        } else {
            baseTabView
        }
    }

    private var baseTabView: some View {
        TabView(selection: $tabBarSelection) {
            DashboardView()
                .hidesNativeTabBar(sizeClass == .regular)
                .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }
                .tag(AppTab.dashboard)
            ExpenseListView()
                .hidesNativeTabBar(sizeClass == .regular)
                .tabItem { Label("Expenses", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.expenses)
            InboxView()
                .hidesNativeTabBar(sizeClass == .regular)
                .tabItem { Label("Inbox", systemImage: "tray.fill") }
                .tag(AppTab.inbox)
            // Placeholder like `.more` below: selecting AI bounces straight back off this tab
            // and opens the full-screen page instead, so this content never shows.
            Color.clear
                .hidesNativeTabBar(sizeClass == .regular)
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag(AppTab.ai)
            Color.clear
                .hidesNativeTabBar(sizeClass == .regular)
                .tabItem { Label("Menu", systemImage: "line.3.horizontal") }
                .tag(AppTab.more)
        }
    }

    // MARK: - Regular layout

    private var iPadSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(AppTab.allCases, id: \.self, selection: sidebarSelection) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationTitle("CharmFi")
            .onChange(of: selectedTab) {
                columnVisibility = .detailOnly
            }
        } detail: {
            switch selectedTab {
            case .dashboard: DashboardView()
            case .expenses: ExpenseListView()
            case .inbox: InboxView()
            // Unreachable: `select(_:)` routes these to the AI page / menu sheet, never storing them.
            case .ai, .more: EmptyView()
            }
        }
        // detailOnly + prominentDetail = sidebar overlays as a backdrop in portrait,
        // slides out as a panel in landscape
        .navigationSplitViewStyle(.prominentDetail)
    }
}

enum AppTab: String, CaseIterable {
    case dashboard, expenses, inbox, ai, more

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .expenses: "Expenses"
        case .inbox: "Inbox"
        case .ai: "AI"
        case .more: "Menu"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "chart.bar.fill"
        case .expenses: "list.bullet.rectangle"
        case .inbox: "tray.fill"
        case .ai: "sparkles"
        case .more: "line.3.horizontal"
        }
    }
}
