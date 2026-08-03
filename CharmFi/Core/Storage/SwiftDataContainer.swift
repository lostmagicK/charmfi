import SwiftData

@MainActor
final class SwiftDataContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            CachedEmailPattern.self,
            CachedMerchantRule.self,
            ProcessedGmailMessage.self,
            StoredAiChatMessage.self
        ])
        let config = ModelConfiguration("CharmFi", schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: config)
    }()
}
