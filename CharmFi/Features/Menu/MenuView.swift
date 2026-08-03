import SwiftUI

enum MenuDestination: String, Identifiable {
    /// `ai` has no tile in the grid below — it is reached from the AI tab, which opens it as a
    /// page rather than switching tabs so the tab bar doesn't sit on top of the composer.
    case ai, budgets, income, mutuus, paymentAccounts, merchantRules, settings
    var id: String { rawValue }

    @ViewBuilder
    var destinationView: some View {
        switch self {
        case .ai: AiInsightsView()
        case .budgets: BudgetsView()
        case .income: IncomeView()
        case .mutuus: MutuusView()
        case .paymentAccounts: PaymentAccountsView()
        case .merchantRules: MerchantRulesView()
        case .settings: SettingsView()
        }
    }
}

struct MenuView: View {
    /// Reports the tapped entry to the presenter, which both closes this sheet and opens the
    /// page in one update. Doing it via a binding + `onChange` instead left the sheet on
    /// screen long enough to block the page from appearing.
    let onSelect: (MenuDestination) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    Button { onSelect(.budgets) } label: {
                        MenuGridItem(icon: "chart.pie.fill", label: "Budgets")
                    }
                    Button { onSelect(.income) } label: {
                        MenuGridItem(icon: "banknote", label: "Income")
                    }
                    Button { onSelect(.mutuus) } label: {
                        MenuGridItem(icon: "arrow.left.arrow.right.circle", label: "Mutuus")
                    }
                    Button { onSelect(.paymentAccounts) } label: {
                        MenuGridItem(icon: "creditcard", label: "Payment Accounts")
                    }
                    Button { onSelect(.merchantRules) } label: {
                        MenuGridItem(icon: "wand.and.stars", label: "Merchant Rules")
                    }
                    Button { onSelect(.settings) } label: {
                        MenuGridItem(icon: "gearshape", label: "Settings")
                    }
                }
                .padding(20)
            }
            .navigationTitle("Menu")
            .adaptiveReadableWidth()
        }
    }
}

private struct MenuGridItem: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .frame(width: 56, height: 56)
                .background(Color.accentColor.opacity(0.15))
                .foregroundStyle(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(label)
                .font(.caption)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    MenuView { _ in }
}
