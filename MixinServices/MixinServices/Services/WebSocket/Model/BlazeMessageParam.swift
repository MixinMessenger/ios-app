import Foundation

struct BlazeMessageParam: Codable {

    var conversationId: String? = nil
    var recipientId: String? = nil
    var category: String? = nil
    var data: String? = nil
    var offset: String? = nil

    var status: String? = nil
    var messageId: String? = nil
    var quoteMessageId: String? = nil

    var keys: SignalKeyRequest? = nil
    var recipients: [BlazeMessageParamSession]? = nil
    var messages: [TransferMessage]? = nil

    var sessionId: String? = nil

    var representativeId: String? = nil
    var conversationChecksum: String? = nil
    
    var mentions: [String]? = nil
    
    var trackId: String? = nil
    var jsep: String? = nil
    var recipientIds: [String]? = nil
    var candidate: String? = nil
    
    var silentNotification: Bool = false
    
    var krakenDebugDescription: String {
        "<KrakenParam category: \(category ?? "(null)"), trackId: \(trackId ?? "(null)"), jsep: \(jsep ?? "(null)"), recipientIds: \(recipientIds.debugDescription ?? "(null)"), candidate: \(candidate ?? "(null)")>"
    }
    
    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case recipientId = "recipient_id"
        case category
        case data
        case offset
        case status
        case messageId = "message_id"
        case quoteMessageId = "quote_message_id"

        case keys
        case recipients
        case messages

        case sessionId = "session_id"

        case representativeId = "representative_id"
        case conversationChecksum = "conversation_checksum"
        
        case trackId = "track_id"
        case jsep
        case recipientIds = "recipient_ids"
        case candidate
        
        case silentNotification = "is_silent"
    }
    
}

extension BlazeMessageParam {

    init(messageId: String, status: String) {
        self.messageId = messageId
        self.status = status
    }
    
    init(conversationId: String, recipientId: String, cipherText: String, sessionId: String?) {
        self.messageId = UUID().uuidString.lowercased()
        self.status = MessageStatus.SENT.rawValue
        self.conversationId = conversationId
        self.recipientId = recipientId
        self.data = cipherText
        self.category = MessageCategory.SIGNAL_KEY.rawValue
        self.sessionId = sessionId
    }

    init(consumeSignalKeys recipients: [BlazeMessageParamSession]) {
        self.recipients = recipients
    }

    init(syncSignalKeys keys: SignalKeyRequest) {
        self.keys = keys
    }

    init(messages: [TransferMessage]) {
        self.messages = messages
    }
    
    init(offset: String) {
        self.offset = offset
    }

    init(sessionId: String, conversationId: String, ackMessages: [TransferMessage]) {
        let transferPlainData = PlainJsonMessagePayload(action: PlainDataAction.ACKNOWLEDGE_MESSAGE_RECEIPTS.rawValue, messageId: nil, messages: nil, ackMessages: ackMessages)
        self.messageId = UUID().uuidString.lowercased()
        self.conversationId = conversationId
        self.recipientId = myUserId
        self.category = MessageCategory.PLAIN_JSON.rawValue
        self.data = (try? JSONEncoder().encode(transferPlainData).base64EncodedString()) ?? ""
        self.status = MessageStatus.SENDING.rawValue
        self.sessionId = sessionId
    }

    init(conversationId: String, recipientId: String? = nil, category: String? = nil, data: String? = nil, offset: String? = nil, status: String? = nil, messageId: String? = nil, quoteMessageId: String? = nil, keys: SignalKeyRequest? = nil, recipients: [BlazeMessageParamSession]? = nil, messages: [TransferMessage]? = nil, sessionId: String? = nil, representativeId: String? = nil, checksum: String? = nil) {
        self.conversationId = conversationId
        self.recipientId = recipientId
        self.category = category
        self.data = data
        self.offset = offset

        self.status = status
        self.messageId = messageId
        self.quoteMessageId = quoteMessageId

        self.keys = keys
        self.recipients = recipients
        self.messages = messages

        self.sessionId = sessionId

        self.representativeId = representativeId
        self.conversationChecksum = checksum
    }
    
    init(conversationId: String, category: MessageCategory, trackId: String?, jsep: String?) {
        self.conversationId = conversationId
        self.category = category.rawValue
        self.trackId = trackId
        self.jsep = jsep
    }
    
}
