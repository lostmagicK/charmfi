import Foundation

enum AiErrors {
    static func message(for error: Error, provider: AiProvider) -> String {
        if let missing = error as? MissingAiKeyException {
            return "Add your \(missing.provider.displayName) API key in AI Settings to use this model."
        }
        if let http = error as? AiHttpError {
            switch http.statusCode {
            case 401: return "Your API key was rejected (401). Check it in AI settings."
            case 429: return "Rate limited by \(provider.displayName) (429). Wait a moment and retry."
            default:
                let detail = http.providerMessage.map { ": \($0)" } ?? "."
                return "Request failed (\(http.statusCode))\(detail)"
            }
        }
        return "Couldn't reach \(provider.displayName): \(error.localizedDescription)"
    }
}
