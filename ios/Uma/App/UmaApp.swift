// App/UmaApp.swift — @main entry point

import SwiftUI
import FirebaseCore

@main
struct UmaApp: App {
    @State private var env: AppEnvironment

    init() {
        FirebaseStartup.configureIfAvailable()
        _env = State(initialValue: AppEnvironment())
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environment(env)
                .preferredColorScheme(env.themeMode.colorScheme)
                .task {
                    env.loadBundles()
                    await env.userState.prepareFirebaseSession()
                    await env.squad.restoreSavedSquad()
                }
        }
    }
}

extension ThemeService.Mode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
