import Foundation

public let stogramLocalPremiumEmojiURLPrefix = "tg://emoji?id="

public func stogramLocalPremiumEmojiURL(fileId: Int64) -> String {
    return "\(stogramLocalPremiumEmojiURLPrefix)\(fileId)"
}

public func stogramLocalPremiumEmojiFileId(url: String) -> Int64? {
    guard url.hasPrefix(stogramLocalPremiumEmojiURLPrefix) else {
        return nil
    }
    let value = String(url.dropFirst(stogramLocalPremiumEmojiURLPrefix.count))
        .split(separator: "&", maxSplits: 1, omittingEmptySubsequences: true)
        .first
    return value.flatMap { Int64($0) }
}
