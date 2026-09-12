import Foundation
import Postbox
import SGSimpleSettings

private let stogramProfileSyncURLPrefix = "tg://stogram/profile/"
private let stogramProfileSyncSentPrefix = "stogram.profileSync.sent."
private let stogramProfileSyncReceivedPrefix = "stogram.profileSync.received."

private func stogramProfileSyncRevision(data: Data) -> String {
    var hash: UInt64 = 14695981039346656037
    for byte in data {
        hash ^= UInt64(byte)
        hash = hash &* 1099511628211
    }
    return String(format: "%016llx", hash)
}

public struct StogramProfileSyncPayload: Codable, Equatable {
    public let version: Int
    public let revision: String
    public let nameColor: PeerColorPayload?
    public let backgroundEmojiId: Int64?
    public let profileColor: Int32?
    public let profileBackgroundEmojiId: Int64?
    public let emojiStatus: PeerEmojiStatus?

    public init(
        revision: String,
        nameColor: PeerColorPayload?,
        backgroundEmojiId: Int64?,
        profileColor: Int32?,
        profileBackgroundEmojiId: Int64?,
        emojiStatus: PeerEmojiStatus?
    ) {
        self.version = 1
        self.revision = revision
        self.nameColor = nameColor
        self.backgroundEmojiId = backgroundEmojiId
        self.profileColor = profileColor
        self.profileBackgroundEmojiId = profileBackgroundEmojiId
        self.emojiStatus = emojiStatus
    }
}

public enum PeerColorPayload: Codable, Equatable {
    case preset(Int32)
    case collectible(PeerCollectibleColor)

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: Int32, Codable {
        case preset
        case collectible
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .preset:
            self = .preset(try container.decode(Int32.self, forKey: .value))
        case .collectible:
            self = .collectible(try container.decode(PeerCollectibleColor.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .preset(value):
            try container.encode(Kind.preset, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .collectible(value):
            try container.encode(Kind.collectible, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }
}

private func stogramProfileSyncPayload(for peer: Peer) -> StogramProfileSyncPayload? {
    let nameColor: PeerColor?
    let backgroundEmojiId: Int64?
    let profileColor: PeerNameColor?
    let profileBackgroundEmojiId: Int64?
    let emojiStatus: PeerEmojiStatus?

    switch peer {
    case let user as TelegramUser:
        nameColor = user.nameColor
        backgroundEmojiId = user.backgroundEmojiId
        profileColor = user.profileColor
        profileBackgroundEmojiId = user.profileBackgroundEmojiId
        emojiStatus = user.emojiStatus
    case let channel as TelegramChannel:
        nameColor = channel.nameColor.map { .preset($0) }
        backgroundEmojiId = channel.backgroundEmojiId
        profileColor = channel.profileColor
        profileBackgroundEmojiId = channel.profileBackgroundEmojiId
        emojiStatus = channel.emojiStatus
    default:
        return nil
    }

    let payloadNameColor: PeerColorPayload?
    switch nameColor {
    case let .preset(value):
        payloadNameColor = .preset(value.rawValue)
    case let .collectible(value):
        payloadNameColor = .collectible(value)
    case nil:
        payloadNameColor = nil
    }

    let provisional = StogramProfileSyncPayload(
        revision: "",
        nameColor: payloadNameColor,
        backgroundEmojiId: backgroundEmojiId,
        profileColor: profileColor?.rawValue,
        profileBackgroundEmojiId: profileBackgroundEmojiId,
        emojiStatus: emojiStatus
    )
    guard let data = try? JSONEncoder().encode(provisional) else {
        return nil
    }
    let revision = stogramProfileSyncRevision(data: data)
    return StogramProfileSyncPayload(
        revision: revision,
        nameColor: payloadNameColor,
        backgroundEmojiId: backgroundEmojiId,
        profileColor: profileColor?.rawValue,
        profileBackgroundEmojiId: profileBackgroundEmojiId,
        emojiStatus: emojiStatus
    )
}

public func stogramProfileSyncPayloadForSending(peer: Peer) -> StogramProfileSyncPayload? {
    return stogramProfileSyncPayload(for: peer)
}

private func stogramProfileSyncURL(payload: StogramProfileSyncPayload) -> String? {
    guard let data = try? JSONEncoder().encode(payload) else {
        return nil
    }
    let encoded = data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return stogramProfileSyncURLPrefix + encoded
}

private func stogramProfileSyncPayload(url: String) -> StogramProfileSyncPayload? {
    guard url.hasPrefix(stogramProfileSyncURLPrefix) else {
        return nil
    }
    var encoded = String(url.dropFirst(stogramProfileSyncURLPrefix.count))
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
    guard let data = Data(base64Encoded: encoded),
          let payload = try? JSONDecoder().decode(StogramProfileSyncPayload.self, from: data),
          payload.version == 1,
          !payload.revision.isEmpty else {
        return nil
    }
    return payload
}

public func stogramProfileSyncPayload(for peerId: PeerId) -> StogramProfileSyncPayload? {
    guard let data = UserDefaults.standard.data(forKey: stogramProfileSyncReceivedPrefix + String(peerId.toInt64())) else {
        return nil
    }
    return try? JSONDecoder().decode(StogramProfileSyncPayload.self, from: data)
}

public func stogramProfileSyncNameColor(for payload: StogramProfileSyncPayload) -> PeerColor? {
    switch payload.nameColor {
    case let .preset(value):
        return .preset(PeerNameColor(rawValue: value))
    case let .collectible(value):
        return .collectible(value)
    case nil:
        return nil
    }
}

public func stogramProfileSyncMessage(account: Account, peerId: PeerId, transaction: Transaction) -> EnqueueMessage? {
    guard SGSimpleSettings.shared.stogramModeEnabled && SGSimpleSettings.shared.stogramProfileSyncEnabled,
          peerId.namespace != Namespaces.Peer.SecretChat,
          peerId != account.peerId,
          let peer = transaction.getPeer(account.peerId),
          let payload = stogramProfileSyncPayload(for: peer),
          let url = stogramProfileSyncURL(payload: payload) else {
        return nil
    }

    let sentKey = stogramProfileSyncSentPrefix + String(peerId.toInt64())
    guard UserDefaults.standard.string(forKey: sentKey) != payload.revision else {
        return nil
    }

    let entity = MessageTextEntity(
        range: 0 ..< 1,
        type: .TextUrl(url: url)
    )
    return .message(
        text: "✨",
        attributes: [TextEntitiesMessageAttribute(entities: [entity])],
        inlineStickers: [:],
        mediaReference: nil,
        threadId: nil,
        replyToMessageId: nil,
        replyToStoryId: nil,
        localGroupingKey: nil,
        correlationId: nil,
        bubbleUpEmojiOrStickersets: []
    )
}

public func stogramMarkProfileSyncSent(peerId: PeerId, payload: StogramProfileSyncPayload) {
    UserDefaults.standard.set(payload.revision, forKey: stogramProfileSyncSentPrefix + String(peerId.toInt64()))
}

public func stogramStoreReceivedProfileSync(peerId: PeerId, entities: [MessageTextEntity]) {
    guard SGSimpleSettings.shared.stogramModeEnabled && SGSimpleSettings.shared.stogramProfileSyncEnabled else {
        return
    }
    for entity in entities {
        guard case let .TextUrl(url) = entity.type,
              let payload = stogramProfileSyncPayload(url: url),
              let data = try? JSONEncoder().encode(payload) else {
            continue
        }
        let key = stogramProfileSyncReceivedPrefix + String(peerId.toInt64())
        if let currentData = UserDefaults.standard.data(forKey: key),
           let current = try? JSONDecoder().decode(StogramProfileSyncPayload.self, from: currentData),
           current.revision == payload.revision {
            continue
        }
        UserDefaults.standard.set(data, forKey: key)
    }
}
