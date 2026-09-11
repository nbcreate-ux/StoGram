import Foundation

public let stogramLocalPremiumEmojiURLPrefix = "tg://stogram/emoji/"

public func stogramLocalPremiumEmojiURL(fileId: Int64) -> String {
    return "\(stogramLocalPremiumEmojiURLPrefix)\(fileId)"
}

public func stogramLocalPremiumEmojiFileId(url: String) -> Int64? {
    guard url.hasPrefix(stogramLocalPremiumEmojiURLPrefix) else {
        return nil
    }
    return Int64(String(url.dropFirst(stogramLocalPremiumEmojiURLPrefix.count)))
}
