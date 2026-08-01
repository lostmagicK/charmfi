import SwiftUI
import UIKit

private let navyUI = UIColor(red: 13/255, green: 27/255, blue: 62/255, alpha: 1)
private let navy   = Color(red: 13/255, green: 27/255, blue: 62/255)
private let gold   = Color(red: 212/255, green: 168/255, blue: 85/255)

struct LoginView: View {
    @Environment(AuthState.self) private var authState
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image("CharmFiIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 90, height: 90)
            Spacer().frame(height: 20)
            HStack(spacing: 0) {
                Text("Charm")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                Text("Fi")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(gold)
            }
            Spacer().frame(height: 8)
            HStack(spacing: 6) {
                Rectangle().fill(gold).frame(width: 24, height: 1)
                Text("Every rupee, right where it belongs.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
                Rectangle().fill(gold).frame(width: 24, height: 1)
            }
            Spacer()
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)
            }
            Button {
                Task { await signIn() }
            } label: {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView().tint(.white).scaleEffect(0.85)
                    } else {
                        Image(systemName: "person.badge.key.fill")
                        Text("Sign in")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [gold, Color(red: 180/255, green: 130/255, blue: 50/255)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isLoading)
            .padding(.bottom, 48)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(navy, ignoresSafeAreaEdges: .all)
        .onAppear {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .forEach {
                    $0.backgroundColor = navyUI
                    $0.rootViewController?.view.backgroundColor = navyUI
                    // iOS 16+: remove safe area regions from the hosting controller
                    if let vc = $0.rootViewController {
                        removeSafeAreas(from: vc)
                    }
                }
        }
    }

    private func removeSafeAreas(from vc: UIViewController) {
        vc.view.backgroundColor = navyUI
        if #available(iOS 16.0, *),
           vc.responds(to: NSSelectorFromString("setSafeAreaRegions:")) {
            // SafeAreaRegions([]) rawValue is 0 — clears all safe area contributions
            vc.setValue(UInt(0), forKey: "safeAreaRegions")
        }
        for child in vc.children { removeSafeAreas(from: child) }
    }

    private func signIn() async {
        isLoading = true
        error = nil
        do {
            try await authState.signIn()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}


