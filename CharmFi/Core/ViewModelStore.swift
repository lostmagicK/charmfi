import Foundation

/// A view model that is created from the app's auth state and can be cached for the
/// lifetime of a signed-in session.
@MainActor
protocol AuthedViewModel: AnyObject {
    init(auth: AuthState)
}

/// Session-scoped cache of feature view models, keyed by type.
///
/// Feature views own their view model in `@State`, which SwiftUI throws away whenever the
/// surrounding subtree is rebuilt — most visibly on iPad, where rotating swaps the whole
/// `TabView`/`NavigationSplitView` tree. Resolving through this store means the rebuilt view
/// picks the existing model back up instead of re-fetching everything from scratch.
///
/// Cleared on sign-out so the next account never sees the previous one's data.
@MainActor
final class ViewModelStore {
    static let shared = ViewModelStore()

    private var models: [ObjectIdentifier: AnyObject] = [:]

    private init() {}

    /// Returns the cached model for `type`, creating it on first use.
    ///
    /// `configure` and `isNew` both fire only on that first use — gate the initial network
    /// load on `isNew` so later rebuilds reuse data that has already been fetched.
    func model<T: AuthedViewModel>(_ type: T.Type,
                                   auth: AuthState,
                                   configure: (T) -> Void = { _ in }) -> (model: T, isNew: Bool) {
        let key = ObjectIdentifier(type)
        if let cached = models[key] as? T {
            return (cached, false)
        }
        let created = T(auth: auth)
        configure(created)
        models[key] = created
        return (created, true)
    }

    func reset() {
        models.removeAll()
    }
}
