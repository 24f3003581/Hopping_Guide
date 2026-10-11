// App/AppRoot.swift — root shell + tab navigation with Puja icons

import SwiftUI

struct AppRoot: View {
    @Environment(AppEnvironment.self) private var env
    @State private var mountedTabs: Set<AppTab> = [.map]

    var body: some View {
        if !env.hasOnboarded {
            WelcomeView()
        } else {
            TabView(selection: tabBinding) {
                // Map is always kept mounted for immediate startup readiness and deep linking
                MapTabView()
                    .tabItem {
                        Label("Map", image: "durga_eyes")
                    }
                    .tag(AppTab.map)

                Group {
                    if mountedTabs.contains(.pandals) {
                        PandalsListView()
                    } else {
                        Color.clear
                    }
                }
                .tabItem {
                    Label("Pandals", image: "durga_face")
                }
                .tag(AppTab.pandals)

                Group {
                    if mountedTabs.contains(.routes) {
                        RoutesView()
                    } else {
                        Color.clear
                    }
                }
                .tabItem {
                    Label("Routes", image: "ashtabhuja_variant")
                }
                .tag(AppTab.routes)

                Group {
                    if mountedTabs.contains(.squads) {
                        SquadHubView()
                    } else {
                        Color.clear
                    }
                }
                .tabItem {
                    Label("Squads", image: "dhaki")
                }
                .tag(AppTab.squads)

                Group {
                    if mountedTabs.contains(.helplines) {
                        HelplinesView()
                    } else {
                        Color.clear
                    }
                }
                .tabItem {
                    Label("Helpline", image: "trishul_eyes")
                }
                .tag(AppTab.helplines)
            }
            .tint(PujaColors.durgaRed)
            .onAppear {
                mountedTabs.insert(env.selectedTab)
            }
            .onChange(of: env.selectedTab) { _, newTab in
                mountedTabs.insert(newTab)
            }
        }
    }

    private var tabBinding: Binding<AppTab> {
        Binding(
            get: { env.selectedTab },
            set: { env.selectedTab = $0 }
        )
    }
}

#Preview {
    AppRoot()
        .environment(AppEnvironment())
}
