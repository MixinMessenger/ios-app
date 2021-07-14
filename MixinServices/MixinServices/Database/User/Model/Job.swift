import Foundation
import GRDB

enum JobPriority: Int {
    case SEND_MESSAGE = 18
    case RESEND_MESSAGE = 15
    case SEND_DELIVERED_ACK_MESSAGE = 7
    case SEND_ACK_MESSAGE = 5
}

public enum JobAction: String {
    case REQUEST_RESEND_KEY
    case REQUEST_RESEND_MESSAGES
    case RESEND_MESSAGE
    case RESEND_KEY
    case SEND_NO_KEY
    case SEND_MESSAGE
    case SEND_ACK_MESSAGE
    case SEND_ACK_MESSAGES
    case SEND_DELIVERED_ACK_MESSAGE
    
    case REFRESH_SESSION
    
    case SEND_SESSION_MESSAGE
    case SEND_SESSION_MESSAGES
    
    case RECOVER_ATTACHMENT
    case UPLOAD_ATTACHMENT
    case UPLOAD_TRANSCRIPT_ATTACHMENT
    
    case PENDING_WEBRTC
}

public enum JobCategory: String {
    case WebSocket
    case Http
    case Task
}

public struct Job {
    
    public var orderId: Int?
    public let jobId: String
    public let priority: Int
    public let action: String
    public let category: String
    
    public let userId: String?
    public let blazeMessage: Data?
    public let blazeMessageData: Data?
    public let conversationId: String?
    public let resendMessageId: String?
    public var messageId: String?
    public var status: String?
    public var sessionId: String?
    
    init(jobId: String, action: JobAction, userId: String? = nil, conversationId: String? = nil, resendMessageId: String? = nil, sessionId: String? = nil, blazeMessage: BlazeMessage? = nil) {
        self.jobId = jobId
        switch action {
        case .RESEND_MESSAGE:
            self.category = JobCategory.WebSocket.rawValue
            self.priority = JobPriority.RESEND_MESSAGE.rawValue
        case .SEND_DELIVERED_ACK_MESSAGE:
            self.category = JobCategory.Http.rawValue
            self.priority = JobPriority.SEND_DELIVERED_ACK_MESSAGE.rawValue
        case .SEND_ACK_MESSAGE, .SEND_ACK_MESSAGES:
            self.category = JobCategory.Http.rawValue
            self.priority = JobPriority.SEND_ACK_MESSAGE.rawValue
        case .SEND_SESSION_MESSAGE, .SEND_SESSION_MESSAGES:
            self.category = JobCategory.WebSocket.rawValue
            self.priority = JobPriority.SEND_ACK_MESSAGE.rawValue
        default:
            self.category = JobCategory.WebSocket.rawValue
            self.priority = JobPriority.SEND_MESSAGE.rawValue
        }
        self.action = action.rawValue
        self.userId = userId
        self.conversationId = conversationId
        self.resendMessageId = resendMessageId
        if let message = blazeMessage {
            self.blazeMessage = try! JSONEncoder.default.encode(message)
        } else {
            self.blazeMessage = nil
        }
        self.blazeMessageData = nil
        self.messageId = nil
        self.status = nil
        self.sessionId = sessionId
    }
    
}

extension Job: Codable, DatabaseColumnConvertible, MixinFetchableRecord, MixinEncodableRecord {
    
    public enum CodingKeys: String, CodingKey {
        case orderId
        case jobId = "job_id"
        case priority
        case blazeMessage = "blaze_message"
        case blazeMessageData = "blaze_message_data"
        case action
        case category
        case conversationId = "conversation_id"
        case userId = "user_id"
        case resendMessageId = "resend_message_id"
        case messageId = "message_id"
        case status
        case sessionId = "session_id"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        orderId = try container.decodeIfPresent(Int.self, forKey: .orderId)
        jobId = try container.decode(String.self, forKey: .jobId)
        priority = try container.decode(Int.self, forKey: .priority)
        action = try container.decode(String.self, forKey: .action)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        blazeMessage = try container.decodeIfPresent(Data.self, forKey: .blazeMessage)
        blazeMessageData = try container.decodeIfPresent(Data.self, forKey: .blazeMessageData)
        conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId)
        resendMessageId = try container.decodeIfPresent(String.self, forKey: .resendMessageId)
        messageId = try container.decodeIfPresent(String.self, forKey: .messageId)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
    }
    
}

extension Job: TableRecord, PersistableRecord {
    
    public static let databaseTableName = "jobs"
    
}

extension Job {
    
    func toBlazeMessage() -> BlazeMessage {
        return try! JSONDecoder.default.decode(BlazeMessage.self, from: blazeMessage!)
    }
    
    public func toBlazeMessageData() -> BlazeMessageData {
        return try! JSONDecoder.default.decode(BlazeMessageData.self, from: blazeMessageData!)
    }
    
}

extension Job {
    
    init(message: Message, representativeId: String? = nil, data: String? = nil, silentNotification: Bool = false) {
        let param = BlazeMessageParam(conversationId: message.conversationId,
                                      category: message.category,
                                      data: data,
                                      status: MessageStatus.SENT.rawValue,
                                      messageId: message.messageId,
                                      representativeId: representativeId,
                                      silentNotification: silentNotification)
        let action = BlazeMessageAction.createMessage.rawValue
        let blazeMessage = BlazeMessage(params: param, action: action)
        self.init(jobId: blazeMessage.id, action: .SEND_MESSAGE, blazeMessage: blazeMessage)
    }
    
    init(webRTCMessage message: Message, recipientId: String) {
        let param = BlazeMessageParam(conversationId: message.conversationId,
                                      recipientId: recipientId,
                                      category: message.category,
                                      data: message.content?.base64Encoded(),
                                      messageId: message.messageId,
                                      quoteMessageId: message.quoteMessageId)
        let action = BlazeMessageAction.createCall.rawValue
        let blazeMessage = BlazeMessage(params: param, action: action)
        self.init(jobId: blazeMessage.id, action: .SEND_MESSAGE, blazeMessage: blazeMessage)
    }
    
    public init(pendingWebRTCMessage data: BlazeMessageData) {
        self.jobId = UUID().uuidString.lowercased()
        self.priority = JobPriority.SEND_MESSAGE.rawValue
        self.action = JobAction.PENDING_WEBRTC.rawValue
        self.userId = data.userId
        self.conversationId = data.conversationId
        self.resendMessageId = nil
        self.blazeMessage = nil
        self.blazeMessageData = try! JSONEncoder.default.encode(data)
        self.messageId = data.messageId
        self.status = nil
        self.sessionId = nil
        self.category = JobCategory.Task.rawValue
    }
    
    init(sessionRead conversationId: String, messageId: String, status: String = MessageStatus.READ.rawValue) {
        self.jobId = UUID().uuidString.lowercased()
        self.priority = JobPriority.SEND_ACK_MESSAGE.rawValue
        self.action = JobAction.SEND_SESSION_MESSAGE.rawValue
        self.userId = nil
        self.conversationId = conversationId
        self.resendMessageId = nil
        self.blazeMessage = nil
        self.blazeMessageData = nil
        self.messageId = messageId
        self.status = status
        self.sessionId = nil
        self.category = JobCategory.WebSocket.rawValue
    }
    
    init(attachmentMessage messageId: String, action: JobAction) {
        self.jobId = UUID().uuidString.lowercased()
        self.priority = JobPriority.SEND_ACK_MESSAGE.rawValue
        self.action = action.rawValue
        self.userId = nil
        self.conversationId = nil
        self.resendMessageId = nil
        self.blazeMessage = nil
        self.blazeMessageData = nil
        self.messageId = messageId
        self.status = nil
        self.sessionId = nil
        self.category = JobCategory.Task.rawValue
    }
    
}
