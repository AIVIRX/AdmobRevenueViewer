import Foundation

enum ErrorMessageFormatter {
    static func message(for error: Error) -> String {
        if let apiError = error as? AdMobAPIError, let message = apiError.userMessage {
            return message
        }
        if let apiError = error as? AdSenseAPIError, let message = apiError.userMessage {
            return message
        }
        return error.localizedDescription
    }
}
