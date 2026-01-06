import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .chat

    enum Tab: String, CaseIterable {
        case chat = "记账"
        case transactions = "明细"
        case reports = "报表"
        case family = "家庭"
        case settings = "设置"

        var icon: String {
            switch self {
            case .chat: return "bubble.left.and.text.bubble.right"
            case .transactions: return "list.bullet.rectangle"
            case .reports: return "chart.pie"
            case .family: return "person.3"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatView()
                .tabItem {
                    Label(Tab.chat.rawValue, systemImage: Tab.chat.icon)
                }
                .tag(Tab.chat)

            TransactionListView()
                .tabItem {
                    Label(Tab.transactions.rawValue, systemImage: Tab.transactions.icon)
                }
                .tag(Tab.transactions)

            ReportsView()
                .tabItem {
                    Label(Tab.reports.rawValue, systemImage: Tab.reports.icon)
                }
                .tag(Tab.reports)

            FamilyView()
                .tabItem {
                    Label(Tab.family.rawValue, systemImage: Tab.family.icon)
                }
                .tag(Tab.family)

            SettingsView()
                .tabItem {
                    Label(Tab.settings.rawValue, systemImage: Tab.settings.icon)
                }
                .tag(Tab.settings)
        }
    }
}

#Preview {
    ContentView()
}
