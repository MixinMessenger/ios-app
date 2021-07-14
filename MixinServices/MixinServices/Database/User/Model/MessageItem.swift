import Foundation
import GRDB

public final class MessageItem {
    
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
    public var participantId: String?
    public var snapshotId: String?
    public var name: String?
    public var stickerId: String?
    public var createdAt: String
    
    public var actionName: String?
    
    public var userFullName: String?
    public var userIdentityNumber: String?
    public var userAvatarUrl: String?
    
    public var appId: String?
    
    public var snapshotAmount: String?
    public var snapshotAssetId: String?
    public var snapshotType: String?
    
    public var participantFullName: String?
    public var participantUserId: String?
    
    public var assetUrl: String?
    public var assetType: String?
    public var assetSymbol: String?
    
    public var assetIcon: String?
    public var assetWidth: Int?
    public var assetHeight: Int?
    public var assetCategory: String?
    
    public var sharedUserId: String?
    public var sharedUserFullName: String?
    public var sharedUserIdentityNumber: String?
    public var sharedUserAvatarUrl: String?
    public var sharedUserAppId: String?
    public var sharedUserIsVerified: Bool?
    
    public var quoteMessageId: String?
    public var quoteContent: Data?
    
    public var mentionsJson: Data?
    public var hasMentionRead: Bool?
    
    public lazy var appButtons: [AppButtonData]? = {
        guard category == MessageCategory.APP_BUTTON_GROUP.rawValue, let content = content, let data = Data(base64Encoded: content) else {
            return nil
        }
        return try? JSONDecoder.default.decode([AppButtonData].self, from: data)
    }()
    
    public lazy var appCard: AppCardData? = {
        guard category == MessageCategory.APP_CARD.rawValue, let content = content, let data = Data(base64Encoded: content) else {
            return nil
        }
        return try? JSONDecoder.default.decode(AppCardData.self, from: data)
    }()
    
    public lazy var mentions: MessageMention.Mentions? = {
        guard let json = mentionsJson else {
            return nil
        }
        return try? JSONDecoder.default.decode(MessageMention.Mentions.self, from: json)
    }()
    
    public lazy var mentionedFullnameReplacedContent = makeMentionedFullnameReplacedContent()
    public lazy var markdownControlCodeRemovedContent = makeMarkdownControlCodeRemovedContent()
    
    public lazy var location: Location? = {
        guard category.hasSuffix("_LOCATION") else {
            return nil
        }
        guard let content = content, let json = content.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder.default.decode(Location.self, from: json)
    }()
    
    public lazy var live: TransferLiveData? = {
        guard category.hasSuffix("_LIVE"), let data = content?.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder.default.decode(TransferLiveData.self, from: data)
    }()
    
    public init(messageId: String, conversationId: String, userId: String, category: String, content: String? = nil, mediaUrl: String? = nil, mediaMimeType: String? = nil, mediaSize: Int64? = nil, mediaDuration: Int64? = nil, mediaWidth: Int? = nil, mediaHeight: Int? = nil, mediaHash: String? = nil, mediaKey: Data? = nil, mediaDigest: Data? = nil, mediaStatus: String? = nil, mediaWaveform: Data? = nil, mediaLocalIdentifier: String? = nil, thumbImage: String? = nil, thumbUrl: String? = nil, status: String, participantId: String? = nil, snapshotId: String? = nil, name: String? = nil, stickerId: String? = nil, createdAt: String, actionName: String? = nil, userFullName: String? = nil, userIdentityNumber: String? = nil, userAvatarUrl: String? = nil, appId: String? = nil, snapshotAmount: String? = nil, snapshotAssetId: String? = nil, snapshotType: String? = nil, participantFullName: String? = nil, participantUserId: String? = nil, assetUrl: String? = nil, assetType: String? = nil, assetSymbol: String? = nil, assetIcon: String? = nil, assetWidth: Int? = nil, assetHeight: Int? = nil, assetCategory: String? = nil, sharedUserId: String? = nil, sharedUserFullName: String? = nil, sharedUserIdentityNumber: String? = nil, sharedUserAvatarUrl: String? = nil, sharedUserAppId: String? = nil, sharedUserIsVerified: Bool? = nil, quoteMessageId: String? = nil, quoteContent: Data? = nil, mentionsJson: Data? = nil, hasMentionRead: Bool? = nil) {
        self.messageId = messageId
        self.conversationId = conversationId
        self.userId = userId
        self.category = category
        self.content = content
        self.mediaUrl = mediaUrl
        self.mediaMimeType = mediaMimeType
        self.mediaSize = mediaSize
        self.mediaDuration = mediaDuration
        self.mediaWidth = mediaWidth
        self.mediaHeight = mediaHeight
        self.mediaHash = mediaHash
        self.mediaKey = mediaKey
        self.mediaDigest = mediaDigest
        self.mediaStatus = mediaStatus
        self.mediaWaveform = mediaWaveform
        self.mediaLocalIdentifier = mediaLocalIdentifier
        self.thumbImage = thumbImage
        self.thumbUrl = thumbUrl
        self.status = status
        self.participantId = participantId
        self.snapshotId = snapshotId
        self.name = name
        self.stickerId = stickerId
        self.createdAt = createdAt
        self.actionName = actionName
        self.userFullName = userFullName
        self.userIdentityNumber = userIdentityNumber
        self.userAvatarUrl = userAvatarUrl
        self.appId = appId
        self.snapshotAmount = snapshotAmount
        self.snapshotAssetId = snapshotAssetId
        self.snapshotType = snapshotType
        self.participantFullName = participantFullName
        self.participantUserId = participantUserId
        self.assetUrl = assetUrl
        self.assetType = assetType
        self.assetSymbol = assetSymbol
        self.assetIcon = assetIcon
        self.assetWidth = assetWidth
        self.assetHeight = assetHeight
        self.assetCategory = assetCategory
        self.sharedUserId = sharedUserId
        self.sharedUserFullName = sharedUserFullName
        self.sharedUserIdentityNumber = sharedUserIdentityNumber
        self.sharedUserAvatarUrl = sharedUserAvatarUrl
        self.sharedUserAppId = sharedUserAppId
        self.sharedUserIsVerified = sharedUserIsVerified
        self.quoteMessageId = quoteMessageId
        self.quoteContent = quoteContent
        self.mentionsJson = mentionsJson
        self.hasMentionRead = hasMentionRead
    }
    
    public convenience init(category: String, conversationId: String, createdAt: String) {
        self.init(messageId: UUID().uuidString.lowercased(),
                  conversationId: conversationId,
                  userId: "",
                  category: category,
                  status: MessageStatus.SENDING.rawValue,
                  createdAt: createdAt)
    }
    
}

extension MessageItem: Codable, MixinFetchableRecord {
    
    public enum CodingKeys: String, CodingKey, CaseIterable {
        
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
        case participantId = "participant_id"
        case snapshotId = "snapshot_id"
        case name
        case stickerId = "sticker_id"
        case createdAt = "created_at"
        
        case userFullName
        case userIdentityNumber
        case userAvatarUrl
        
        case appId
        
        case participantFullName
        case participantUserId
        
        case snapshotAmount
        case snapshotAssetId
        case snapshotType
        
        case assetSymbol
        case assetIcon
        
        case assetWidth
        case assetHeight
        case assetUrl
        case assetType
        case assetCategory
        
        case actionName
        
        case sharedUserId
        case sharedUserFullName
        case sharedUserIdentityNumber
        case sharedUserAvatarUrl
        case sharedUserAppId
        case sharedUserIsVerified
        
        case quoteMessageId = "quote_message_id"
        case quoteContent = "quote_content"
        
        case mentionsJson = "mentions"
        case hasMentionRead
    }
    
}

extension MessageItem: MarkdownControlCodeRemovable {
    
    var contentBeforeRemovingMarkdownControlCode: String? {
        content
    }
    
    var isPostContent: Bool {
        category.hasSuffix("_POST")
    }
    
}

extension MessageItem: MentionedFullnameReplaceable {
    
    public var contentBeforeReplacingMentionedFullname: String? {
        content
    }
    
}

extension MessageItem {
    
    public var isExtensionMessage: Bool {
        return category == MessageCategory.EXT_UNREAD.rawValue || category == MessageCategory.EXT_ENCRYPTION.rawValue
    }
    
    public var isSystemMessage: Bool {
        category == MessageCategory.SYSTEM_CONVERSATION.rawValue || category.hasPrefix("KRAKEN_")
    }
    
    public var userIsBot: Bool {
        return !(appId?.isEmpty ?? true)
    }
    
    public var canRecall: Bool {
        guard userId == myUserId, status != MessageStatus.SENDING.rawValue else {
            return false
        }
        guard category == MessageCategory.APP_CARD.rawValue || SendMessageService.recallableSuffices.contains(where: category.hasSuffix) else {
            return false
        }
        guard abs(createdAt.toUTCDate().timeIntervalSinceNow) < 3600 else {
            return false
        }
        return true
    }
    
    public var assetTypeIsJSON: Bool {
        if let type = assetType?.uppercased() {
            return type == "JSON"
        } else {
            return false
        }
    }
    
    public func isRepresentativeMessage(conversation: ConversationItem) -> Bool {
        guard userId != myUserId else {
            return false
        }
        guard conversation.category != ConversationCategory.GROUP.rawValue else {
            return true
        }
        return conversation.ownerId != userId && conversation.category == ConversationCategory.CONTACT.rawValue
    }
    
    public var isListPlayable: Bool {
        ["audio/mpeg", "audio/mp3"].contains(mediaMimeType)
    }
    
}
