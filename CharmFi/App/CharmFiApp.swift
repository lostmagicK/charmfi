import SwiftUI
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    @MainActor
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let authState = AuthState()

        let rootView = RootView(authState: authState)
            .modelContainer(SwiftDataContainer.shared)

        let hostingVC = UIHostingController(rootView: rootView)
        hostingVC.view.backgroundColor = .systemBackground

        let win = UIWindow()
        win.frame = UIScreen.main.bounds
        win.rootViewController = hostingVC
        win.makeKeyAndVisible()
        self.window = win

        // Wire up the ~6h background Gmail scan. register() must run before launch completes.
        BackgroundSyncManager.shared.authState = authState
        BackgroundSyncManager.shared.register()
        BackgroundSyncManager.shared.schedule()

        Task { await authState.restoreSession() }
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Foreground catch-up: scan Gmail now if it's been 6h+ since the last sync.
        Task { @MainActor in
            await BackgroundSyncManager.shared.runForegroundCatchUpIfNeeded()
        }
    }

    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if let authFlow = KeycloakAuthService.shared.currentAuthorizationFlow,
           authFlow.resumeExternalUserAgentFlow(with: url) {
            KeycloakAuthService.shared.currentAuthorizationFlow = nil
            return true
        }
        return false
    }
}

struct RootView: View {
    @State var authState: AuthState
    @AppStorage("appColorScheme") private var colorSchemeValue: Int = 0

    private var preferredColorScheme: ColorScheme? {
        switch colorSchemeValue {
        case 1: .light
        case 2: .dark
        default: nil
        }
    }

    var body: some View {
        Group {
            if authState.isAuthenticated {
                ContentView().environment(authState)
            } else {
                LoginView().environment(authState)
            }
        }
        .preferredColorScheme(preferredColorScheme)
        .onChange(of: authState.isAuthenticated) { _, isAuthenticated in
            // Feature view models are cached for the session; drop them so the next
            // sign-in doesn't reuse the previous account's data.
            if !isAuthenticated { ViewModelStore.shared.reset() }
        }
    }
}
