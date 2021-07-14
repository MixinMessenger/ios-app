import Foundation

public struct BlazeMessageData: Codable {
    
    public let conversationId: String
    public var userId: String
    public var messageId: String
    public let category: String
    public let data: String
    public let status: String
    public let createdAt: String
    public let updatedAt: String
    public let source: String
    public let quoteMessageId: String
    public let representativeId: String
    public let sessionId: String
    public let silentNotification: Bool
    
    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case userId = "user_id"
        case messageId = "message_id"
        case category
        case data
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case source
        case quoteMessageId = "quote_message_id"
        case representativeId = "representative_id"
        case sessionId = "session_id"
        case silentNotification = "is_silent"
    }
    
}

public extension BlazeMessageData {
    
    func getSenderId() -> String {
        guard !representativeId.isEmpty else {
            return userId
        }
        return representativeId
    }
    
    func getDataUserId() -> String? {
        return representativeId.isEmpty ? nil : userId
    }
    
}
