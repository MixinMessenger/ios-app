import Foundation
import GRDB

public struct Message {
    
    public var messageId: String
    public var conversationId: String
    public var userId: String
    public var category: String
    public var content: String?
    public var mediaUrl: String?
    public var mediaMimeType: String?
    public var mediaSize: Int64?
    public var mediaDuration: Int64?
    public var mediaWidth: Int?
    public var mediaHeight: Int?
    public var mediaHash: String?
    public var mediaKey: Data?
    public var mediaDigest: Data?
    public var mediaStatus: String?
    public var mediaWaveform: Data?
    public var mediaLocalIdentifier: String?
    public var thumbImage: String?
    public var thumbUrl: String?
    public var status: String
    public var action: String?
    public var participantId: String?
    public var snapshotId: String?
    public var name: String?
    public var stickerId: String?
    public var sharedUserId: String?
    public var quoteMessageId: String?
    public var quoteContent: Data?
    public var createdAt: String
    
}

extension Message: Codable, DatabaseColumnConvertible, MixinFetchableRecord, MixinEncodableRecord {
    
    public enum CodingKeys: String, CodingKey {
        case messageId = "id"
        case conversationId = "conversation_id"
        case userId = "user_id"
        case category
        case content
        case mediaUrl = "media_url"
        case mediaMimeType = "media_mime_type"
        case mediaSize = "media_size"
        case mediaDuration = "media_duration"
        case mediaWidth = "media_width"
        case mediaHeight = "media_height"
        case mediaHash = "media_hash"
        case mediaKey = "media_key"
        case mediaDigest = "media_digest"
        case mediaStatus = "media_status"
        case mediaWaveform = "media_waveform"
        case mediaLocalIdentifier = "media_local_id"
        case thumbImage = "thumb_image"
        case thumbUrl = "thumb_url"
        case status
        case action
        case participantId = "participant_id"
        case snapshotId = "snapshot_id"
        case name
        case stickerId = "sticker_id"
        case sharedUserId = "shared_user_id"
        case quoteMessageId = "quote_message_id"
        case quoteContent = "quote_content"
        case createdAt = "created_at"
    }
    
}

extension Message: TableRecord, PersistableRecord {
    
    public static let databaseTableName = "messages"
    public static let ftsTableName = "messages_fts_v3"
    
}

extension Message {
    
    public func shouldUpload() -> Bool {
        return userId == myUserId && (mediaUrl != nil || mediaLocalIdentifier != nil)
    }
    
    public static func createMessage(messageId: String, conversationId: String, userId: String, category: String, content: String? = nil, mediaUrl: String? = nil, mediaMimeType: String? = nil, mediaSize: Int64? = nil, mediaDuration: Int64? = nil, mediaWidth: Int? = nil, mediaHeight: Int? = nil, mediaHash: String? = nil, mediaKey: Data? = nil, mediaDigest: Data? = nil, mediaStatus: String? = nil, mediaWaveform: Data? = nil, mediaLocalIdentifier: String? = nil, thumbImage: String? = nil, thumbUrl: String? = nil, status: String, action: String? = nil, participantId: String? = nil, snapshotId: String? = nil, name: String? = nil, stickerId: String? = nil, sharedUserId: String? = nil, quoteMessageId: String? = nil, quoteContent: Data? = nil, createdAt: String) -> Message {
        return Message(messageId: messageId, conversationId: conversationId, userId: userId, category: category, content: content, mediaUrl: mediaUrl, mediaMimeType: mediaMimeType, mediaSize: mediaSize, mediaDuration: mediaDuration, mediaWidth: mediaWidth, mediaHeight: mediaHeight, mediaHash: mediaHash, mediaKey: mediaKey, mediaDigest: mediaDigest, mediaStatus: mediaStatus, mediaWaveform: mediaWaveform, mediaLocalIdentifier: mediaLocalIdentifier, thumbImage: thumbImage, thumbUrl: thumbUrl, status: status, action: action, participantId: participantId, snapshotId: snapshotId, name: name, stickerId: stickerId, sharedUserId: sharedUserId, quoteMessageId: quoteMessageId, quoteContent: quoteContent, createdAt: createdAt)
    }
    
    public static func getStatus(data: BlazeMessageData) -> String {
        return data.userId == myUserId ? MessageStatus.SENT.rawValue : MessageStatus.DELIVERED.rawValue
    }
    
    public static func createMessage(snapshotMesssage snapshot: Snapshot, data: BlazeMessageData) -> Message {
        return createMessage(messageId: data.messageId, conversationId: data.conversationId, userId: data.userId, category: data.category, status: MessageStatus.DELIVERED.rawValue, action: snapshot.type, snapshotId: snapshot.snapshotId, createdAt: data.createdAt)
    }
    
    public static func createMessage(textMessage plainText: String, data: BlazeMessageData) -> Message {
        let quoteMessageId = data.quoteMessageId.isEmpty ? nil : data.quoteMessageId
        return createMessage(messageId: data.messageId, conversationId: data.conversationId, userId: data.getSenderId(), category: data.category, content: plainText, status: getStatus(data: data), quoteMessageId: quoteMessageId, createdAt: data.createdAt)
    }
    
    public static func createMessage(systemMessage action: String?, participantId: String?, userId: String, data: BlazeMessageData) -> Message {
        return createMessage(messageId: data.messageId, conversationId: data.conversationId, userId: userId, category: data.category, status: MessageStatus.DELIVERED.rawValue, action: action, participantId: participantId, createdAt: data.createdAt)
    }
    
    public static func createMessage(appMessage data: BlazeMessageData) -> Message {
        return createMessage(messageId: data.messageId, conversationId: data.conversationId, userId: data.getSenderId(), category: data.category, content: data.data, status: getStatus(data: data), createdAt: data.createdAt)
    }
    
    public static func createMessage(stickerData: TransferStickerData, data: BlazeMessageData) -> Message {
        return createMessage(messageId: data.messageId, conversationId: data.conversationId, userId: data.getSenderId(), category: data.category, status: getStatus(data: data), stickerId: stickerData.stickerId, createdAt: data.createdAt)
    }
    
    public static func createMessage(contactData: TransferContactData, data: BlazeMessageData) -> Message {
        return createMessage(messageId: data.messageId,
                             conversationId: data.conversationId,
                             userId: data.getSenderId(),
                             category: data.category,
                             status: getStatus(data: data),
                             sharedUserId: contactData.userId,
                             quoteMessageId: data.quoteMessageId,
                             createdAt: data.createdAt)
    }
    
    public static func createMessage(mediaData: TransferAttachmentData, data: BlazeMessageData) -> Message {
        return createMessage(messageId: data.messageId,
                             conversationId: data.conversationId,
                             userId: data.getSenderId(),
                             category: data.category,
                             content: mediaData.attachmentId,
                             mediaMimeType: mediaData.mimeType,
                             mediaSize: mediaData.size,
                             mediaDuration: mediaData.duration,
                             mediaWidth: mediaData.width,
                             mediaHeight: mediaData.height,
                             mediaKey: mediaData.key,
                             mediaDigest: mediaData.digest,
                             mediaStatus: MediaStatus.PENDING.rawValue,
                             mediaWaveform: mediaData.waveform,
                             thumbImage: mediaData.thumbnail,
                             status: MessageStatus.DELIVERED.rawValue,
                             name: mediaData.name,
                             quoteMessageId: data.quoteMessageId,
                             createdAt: data.createdAt)
    }
    
    public static func createMessage(liveData: TransferLiveData, content: String?, data: BlazeMessageData) -> Message {
        createMessage(messageId: data.messageId,
                      conversationId: data.conversationId,
                      userId: data.getSenderId(),
                      category: data.category,
                      content: content,
                      mediaUrl: liveData.url,
                      mediaWidth: liveData.width,
                      mediaHeight: liveData.height,
                      thumbUrl: liveData.thumbUrl,
                      status: getStatus(data: data),
                      createdAt: data.createdAt)
    }
    
    public static func createLocationMessage(content: String, data: BlazeMessageData) -> Message {
        return createMessage(messageId: data.messageId,
                             conversationId: data.conversationId,
                             userId: data.getSenderId(),
                             category: data.category,
                             content: content,
                             mediaMimeType: nil,
                             mediaSize: nil,
                             mediaDuration: nil,
                             mediaWidth: nil,
                             mediaHeight: nil,
                             mediaKey: nil,
                             mediaDigest: nil,
                             mediaStatus: nil,
                             mediaWaveform: nil,
                             thumbImage: nil,
                             status: MessageStatus.DELIVERED.rawValue,
                             name: nil,
                             quoteMessageId: data.quoteMessageId,
                             createdAt: data.createdAt)
    }
    
    public static func createTranscriptMessage(content: String, mediaStatus: MediaStatus, data: BlazeMessageData) -> Message {
        return createMessage(messageId: data.messageId,
                             conversationId: data.conversationId,
                             userId: data.getSenderId(),
                             category: data.category,
                             content: content,
                             mediaMimeType: nil,
                             mediaSize: nil,
                             mediaDuration: nil,
                             mediaWidth: nil,
                             mediaHeight: nil,
                             mediaKey: nil,
                             mediaDigest: nil,
                             mediaStatus: mediaStatus.rawValue,
                             mediaWaveform: nil,
                             thumbImage: nil,
                             status: MessageStatus.DELIVERED.rawValue,
                             name: nil,
                             quoteMessageId: data.quoteMessageId,
                             createdAt: data.createdAt)
    }
    
    public static func createWebRTCMessage(data: BlazeMessageData, category: MessageCategory, status: MessageStatus) -> Message {
        return createMessage(messageId: data.messageId, conversationId: data.conversationId, userId: data.getSenderId(), category: category.rawValue, status: status.rawValue, quoteMessageId: data.quoteMessageId, createdAt: data.createdAt)
    }
    
    public static func createWebRTCMessage(quote: BlazeMessageData, category: MessageCategory, status: MessageStatus) -> Message {
        return createMessage(messageId: UUID().uuidString.lowercased(), conversationId: quote.conversationId, userId: myUserId, category: category.rawValue, status: status.rawValue, quoteMessageId: quote.messageId, createdAt: Date().toUTCString())
    }
    
    public static func createWebRTCMessage(messageId: String = UUID().uuidString.lowercased(), conversationId: String, userId: String = myUserId, category: MessageCategory, content: String? = nil, mediaDuration: Int64? = nil, status: MessageStatus, quoteMessageId: String? = nil) -> Message {
        return createMessage(messageId: messageId, conversationId: conversationId, userId: userId, category: category.rawValue, content: content, mediaDuration: mediaDuration, status: status.rawValue, quoteMessageId: quoteMessageId, createdAt: Date().toUTCString())
    }
    
    public static func createKrakenMessage(conversationId: String, userId: String, category: MessageCategory, mediaDuration: Int64? = nil, status: MessageStatus.RawValue = MessageStatus.READ.rawValue, createdAt: String) -> Message {
        createMessage(messageId: UUID().uuidString,
                      conversationId: conversationId,
                      userId: userId,
                      category: category.rawValue,
                      mediaDuration: mediaDuration,
                      status: status,
                      createdAt: createdAt)
    }
    
    public static func createMessage(messageId: String = UUID().uuidString.lowercased(), category: String, conversationId: String, createdAt: String = Date().toUTCString(), userId: String) -> Message {
        return createMessage(messageId: messageId, conversationId: conversationId, userId: userId, category: category, status: MessageStatus.SENDING.rawValue, createdAt: createdAt)
    }
    
    public static func createMessage(message: MessageItem) -> Message {
        return Message(messageId: message.messageId, conversationId: message.conversationId, userId: message.userId, category: message.category, content: message.content, mediaUrl: message.mediaUrl, mediaMimeType: message.mediaMimeType, mediaSize: message.mediaSize, mediaDuration: message.mediaDuration, mediaWidth: message.mediaWidth, mediaHeight: message.mediaHeight, mediaHash: message.mediaHash, mediaKey: message.mediaKey, mediaDigest: message.mediaDigest, mediaStatus: message.mediaStatus, mediaWaveform: message.mediaWaveform, mediaLocalIdentifier: message.mediaLocalIdentifier, thumbImage: message.thumbImage, thumbUrl: message.thumbUrl, status: message.status, action: message.actionName, participantId: message.participantId, snapshotId: message.snapshotId, name: message.name, stickerId: message.stickerId, sharedUserId: message.sharedUserId, quoteMessageId: message.quoteMessageId, quoteContent: message.quoteContent, createdAt: message.createdAt)
    }
    
}

public enum MessageCategory: String, Decodable {
    
    case SIGNAL_KEY
    case SIGNAL_TEXT
    case SIGNAL_IMAGE
    case SIGNAL_VIDEO
    case SIGNAL_DATA
    case SIGNAL_STICKER
    case SIGNAL_CONTACT
    case SIGNAL_AUDIO
    case SIGNAL_LIVE
    case SIGNAL_POST
    case SIGNAL_LOCATION
    case SIGNAL_TRANSCRIPT
    case PLAIN_TEXT
    case PLAIN_IMAGE
    case PLAIN_VIDEO
    case PLAIN_DATA
    case PLAIN_STICKER
    case PLAIN_CONTACT
    case PLAIN_JSON
    case PLAIN_AUDIO
    case PLAIN_LIVE
    case PLAIN_POST
    case PLAIN_LOCATION
    case PLAIN_TRANSCRIPT
    case APP_CARD
    case APP_BUTTON_GROUP
    case SYSTEM_CONVERSATION
    case SYSTEM_ACCOUNT_SNAPSHOT
    case SYSTEM_SESSION
    case SYSTEM_USER
    case SYSTEM_CIRCLE
    case WEBRTC_AUDIO_OFFER
    case WEBRTC_AUDIO_ANSWER
    case WEBRTC_AUDIO_CANCEL
    case WEBRTC_AUDIO_DECLINE
    case WEBRTC_AUDIO_BUSY
    case WEBRTC_AUDIO_FAILED
    case WEBRTC_AUDIO_END
    case WEBRTC_ICE_CANDIDATE
    case MESSAGE_RECALL
    case KRAKEN_INVITE
    case KRAKEN_PUBLISH
    case KRAKEN_SUBSCRIBE
    case KRAKEN_ANSWER
    case KRAKEN_TRICKLE
    case KRAKEN_END
    case KRAKEN_CANCEL
    case KRAKEN_DECLINE
    case KRAKEN_RESTART
    case EXT_UNREAD
    case EXT_ENCRYPTION
    case UNKNOWN
    
    public static func isLegal(category: String) -> Bool {
        guard let category = MessageCategory(rawValue: category) else {
            return false
        }
        switch category {
        case .UNKNOWN, .EXT_UNREAD, .EXT_ENCRYPTION:
            return false
        default:
            return true
        }
    }
    
    public static let allMediaCategories: [MessageCategory] = [
        .SIGNAL_IMAGE, .PLAIN_IMAGE,
        .SIGNAL_VIDEO, .PLAIN_VIDEO,
        .SIGNAL_AUDIO, .PLAIN_AUDIO,
        .SIGNAL_DATA, .PLAIN_DATA
    ]
    
    public static let allMediaCategoriesString: Set<String> = Set(allMediaCategories.map(\.rawValue))
    
    public static let endCallCategories: [MessageCategory] = [
        .WEBRTC_AUDIO_END,
        .WEBRTC_AUDIO_BUSY,
        .WEBRTC_AUDIO_CANCEL,
        .WEBRTC_AUDIO_FAILED,
        .WEBRTC_AUDIO_DECLINE
    ]
    
    public static let krakenCategories: Set<String> = {
        let categories: [MessageCategory] = [
            .KRAKEN_PUBLISH,
            .KRAKEN_INVITE,
            .KRAKEN_CANCEL,
            .KRAKEN_DECLINE,
            .KRAKEN_END
        ]
        return Set(categories.map(\.rawValue))
    }()
    
    // ⚠️ Database table creation depends on this, look after database when modifying
    public static let ftsAvailable: Set<Self> = [
        .SIGNAL_TEXT, .PLAIN_TEXT,
        .SIGNAL_POST, .PLAIN_POST,
        .SIGNAL_DATA, .PLAIN_DATA,
        .SIGNAL_TRANSCRIPT, .PLAIN_TRANSCRIPT
    ]
    
    public static let ftsAvailableCategoryStrings: Set<String> = Set(ftsAvailable.map(\.rawValue))
    public static let ftsAvailableCategorySequence = "('" + ftsAvailableCategoryStrings.joined(separator: "', '") + "')"
    
}

public enum MessageStatus: String, Codable {
    case SENDING
    case SENT
    case DELIVERED
    case READ
    case UNKNOWN
    case FAILED
    
    public static func getOrder(messageStatus: String) -> Int {
        switch messageStatus {
        case MessageStatus.SENDING.rawValue:
            return 0
        case MessageStatus.SENT.rawValue:
            return 1
        case MessageStatus.FAILED.rawValue:
            return 2
        case MessageStatus.DELIVERED.rawValue:
            return 3
        case MessageStatus.READ.rawValue:
            return 4
        default:
            return -1
        }
    }
}

public enum MessageMentionStatus: String {
    case MENTION_READ
}

public enum MediaStatus: String {
    case PENDING
    case DONE
    case CANCELED
    case EXPIRED
    case READ
}
