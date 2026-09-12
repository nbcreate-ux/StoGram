import Foundation
import Postbox

public struct StogramMessageEditHistoryEntry: Codable {
    public let date: Int32
    public let text: String
    
    public init(date: Int32, text: String) {
        self.date = date
        self.text = text
    }
}

private func stogramMessageHistoryKey(_ id: MessageId) -> String {
    return "stogram.messageHistory.\(id.peerId.toInt64()).\(id.namespace).\(id.id)"
}

public func stogramRecordMessageEdit(_ message: Message) {
    let key = stogramMessageHistoryKey(message.id)
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    var entries = (UserDefaults.standard.data(forKey: key).flatMap { try? decoder.decode([StogramMessageEditHistoryEntry].self, from: $0) }) ?? []
    guard entries.last?.text != message.text else {
        return
    }
    entries.append(StogramMessageEditHistoryEntry(date: message.timestamp, text: message.text))
    if entries.count > 50 {
        entries.removeFirst(entries.count - 50)
    }
    if let data = try? encoder.encode(entries) {
        UserDefaults.standard.set(data, forKey: key)
    }
}

public func stogramMessageEditHistory(_ id: MessageId) -> [StogramMessageEditHistoryEntry] {
    let key = stogramMessageHistoryKey(id)
    guard let data = UserDefaults.standard.data(forKey: key) else {
        return []
    }
    return (try? JSONDecoder().decode([StogramMessageEditHistoryEntry].self, from: data)) ?? []
}
