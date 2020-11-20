import WCDBSwift
import UIKit

public final class MessageDAO {
    
    public enum UserInfoKey {
        public static let conversationId = "conv_id"
        public static let message = "msg"
        public static let messsageSource = "msg_source"
    }
    
    public static let shared = MessageDAO()
    
    public static let didInsertMessageNotification = Notification.Name("one.mixin.services.did.insert.msg")
    public static let didRedecryptMessageNotification = Notification.Name("one.mixin.services.did.redecrypt.msg")
    
    static let sqlTriggerLastMessageInsert = """
    CREATE TRIGGER IF NOT EXISTS conversation_last_message_update AFTER INSERT ON messages
    BEGIN
        UPDATE conversations SET last_message_id = new.id, last_message_created_at = new.created_at WHERE conversation_id = new.conversation_id;
    END
    """
    static let sqlTriggerLastMessageDelete = """
    CREATE TRIGGER IF NOT EXISTS conversation_last_message_delete AFTER DELETE ON messages
    BEGIN
        UPDATE conversations SET last_message_id = (select id from messages where conversation_id = old.conversation_id order by created_at DESC limit 1) WHERE conversation_id = old.conversation_id;
    END
    """
    static let sqlQueryLastUnreadMessageTime = """
        SELECT created_at FROM messages
        WHERE conversation_id = ? AND status = 'DELIVERED' AND user_id != ?
        ORDER BY created_at DESC
        LIMIT 1
    """
    static let sqlQueryFullMessage = """
    SELECT m.id, m.conversation_id, m.user_id, m.category, m.content, m.media_url, m.media_mime_type,
        m.media_size, m.media_duration, m.media_width, m.media_height, m.media_hash, m.media_key,
        m.media_digest, m.media_status, m.media_waveform, m.media_local_id, m.thumb_image, m.thumb_url, m.status, m.participant_id, m.snapshot_id, m.name,
        m.sticker_id, m.created_at, u.full_name as userFullName, u.identity_number as userIdentityNumber, u.avatar_url as userAvatarUrl, u.app_id as appId,
               u1.full_name as participantFullName, u1.user_id as participantUserId,
               s.amount as snapshotAmount, s.asset_id as snapshotAssetId, s.type as snapshotType, a.symbol as assetSymbol, a.icon_url as assetIcon,
               st.asset_width as assetWidth, st.asset_height as assetHeight, st.asset_url as assetUrl, st.asset_type as assetType, alb.category as assetCategory,
               m.action as actionName, m.shared_user_id as sharedUserId, su.full_name as sharedUserFullName, su.identity_number as sharedUserIdentityNumber, su.avatar_url as sharedUserAvatarUrl, su.app_id as sharedUserAppId, su.is_verified as sharedUserIsVerified, m.quote_message_id, m.quote_content,
        mm.mentions, mm.has_read as hasMentionRead
    FROM messages m
    LEFT JOIN users u ON m.user_id = u.user_id
    LEFT JOIN users u1 ON m.participant_id = u1.user_id
    LEFT JOIN snapshots s ON m.snapshot_id = s.snapshot_id
    LEFT JOIN assets a ON s.asset_id = a.asset_id
    LEFT JOIN stickers st ON m.sticker_id = st.sticker_id
    LEFT JOIN albums alb ON alb.album_id = (
        SELECT album_id FROM sticker_relationships sr WHERE sr.sticker_id = m.sticker_id LIMIT 1
    )
    LEFT JOIN users su ON m.shared_user_id = su.user_id
    LEFT JOIN message_mentions mm ON m.id = mm.message_id
    """
    private static let sqlQueryFirstNMessages = """
    \(sqlQueryFullMessage)
    WHERE m.conversation_id = ?
    ORDER BY m.created_at ASC
    LIMIT ?
    """
    private static let sqlQueryLastNMessages = """
    \(sqlQueryFullMessage)
    WHERE m.conversation_id = ?
    ORDER BY m.created_at DESC
    LIMIT ?
    """
    static let sqlQueryFullMessageBeforeRowId = """
    \(sqlQueryFullMessage)
    WHERE m.conversation_id = ? AND m.ROWID < ?
    ORDER BY m.created_at DESC
    LIMIT ?
    """
    static let sqlQueryFullMessageAfterRowId = """
    \(sqlQueryFullMessage)
    WHERE m.conversation_id = ? AND m.ROWID > ?
    ORDER BY m.created_at ASC
    LIMIT ?
    """
    static let sqlQueryFullAudioMessages = """
    \(sqlQueryFullMessage)
    WHERE m.conversation_id = ? AND m.category in ('SIGNAL_AUDIO', 'PLAIN_AUDIO')
    """
    static let sqlQueryFullDataMessages = """
    \(sqlQueryFullMessage)
    WHERE m.conversation_id = ? AND m.category in ('SIGNAL_DATA', 'PLAIN_DATA')
    """
    static let sqlQueryFullMessageById = sqlQueryFullMessage + " WHERE m.id = ?"
    static let sqlQueryQuoteMessageById = """
    \(sqlQueryFullMessage)
    WHERE m.id = ? AND m.status <> 'FAILED'
    """
    private static let sqlUpdateOldStickers = """
    UPDATE messages SET sticker_id = (
        SELECT s.sticker_id FROM stickers s
        INNER JOIN sticker_relationships sa ON sa.sticker_id = s.sticker_id
        INNER JOIN albums a ON a.album_id = sa.album_id
        WHERE a.album_id = messages.album_id AND s.name = messages.name
    ) WHERE category LIKE '%_STICKER' AND ifnull(sticker_id, '') = ''
    """
    private static let sqlUpdateUnseenMessageCount = """
    UPDATE conversations SET unseen_message_count = (
        SELECT count(*) FROM messages
        WHERE conversation_id = ? AND status = 'DELIVERED' AND user_id != ?
    ) WHERE conversation_id = ?
    """

    private let updateMediaStatusQueue = DispatchQueue(label: "one.mixin.services.queue.media.status.queue")

    public func getMediaUrls(categories: [MessageCategory]) -> [String] {
        let condition: Condition = Message.Properties.category.in(categories.map({ $0.rawValue }))
        return MixinDatabase.shared.getStringValues(column: Message.Properties.mediaUrl.asColumnResult(),
                                                    tableName: Message.tableName,
                                                    condition: condition)
    }

    public func getMediaUrls(conversationId: String, categories: [MessageCategory]) -> [String: String] {
        let condition: Condition = Message.Properties.conversationId == conversationId && Message.Properties.category.in(categories.map({ $0.rawValue }))
        return MixinDatabase.shared.getDictionary(key: Message.Properties.mediaUrl.asColumnResult(), value: Message.Properties.category.asColumnResult(), tableName: Message.tableName, condition: condition)
    }

    public func getDownloadedMediaUrls(categories: [MessageCategory], offset: Offset, limit: Limit) -> [String: String] {
        let condition: Condition = Message.Properties.category.in(categories.map{ $0.rawValue }) && Message.Properties.mediaStatus == MediaStatus.DONE.rawValue
        return MixinDatabase.shared.getDictionary(key: Message.Properties.messageId.asColumnResult(), value: Message.Properties.mediaUrl.asColumnResult(), tableName: Message.tableName, condition: condition, orderBy: [Message.Properties.createdAt.asOrder(by: .descending)], offset: offset, limit: limit)
    }

    public func deleteMediaMessages(conversationId: String, categories: [MessageCategory]) {
        MixinDatabase.shared.delete(table: Message.tableName, condition: Message.Properties.conversationId == conversationId && Message.Properties.category.in(categories.map({ $0.rawValue })))
    }
    
    public func findFailedMessages(conversationId: String, userId: String) -> [String] {
        return MixinDatabase.shared.getStringValues(column: Message.Properties.messageId.asColumnResult(), tableName: Message.tableName, condition: Message.Properties.conversationId == conversationId && Message.Properties.userId == userId && Message.Properties.status == MessageStatus.FAILED.rawValue, orderBy: [Message.Properties.createdAt.asOrder(by: .descending)], limit: 1000)
    }
    
    public func updateMessageContentAndMediaStatus(content: String, mediaStatus: MediaStatus, messageId: String, conversationId: String) {
        guard MixinDatabase.shared.update(maps: [(Message.Properties.content, content), (Message.Properties.mediaStatus, mediaStatus.rawValue)], tableName: Message.tableName, condition: Message.Properties.messageId == messageId && Message.Properties.category != MessageCategory.MESSAGE_RECALL.rawValue) else {
            return
        }
        let change = ConversationChange(conversationId: conversationId, action: .updateMediaStatus(messageId: messageId, mediaStatus: mediaStatus))
        NotificationCenter.default.afterPostOnMain(name: .ConversationDidChange, object: change)
    }
    
    public func update(quoteContent: Data, for messageId: String) {
        MixinDatabase.shared.update(maps: [(Message.Properties.quoteContent, quoteContent)],
                                    tableName: Message.tableName,
                                    condition: Message.Properties.messageId == messageId)
    }
    
    public func isExist(messageId: String) -> Bool {
        return MixinDatabase.shared.isExist(type: Message.self, condition: Message.Properties.messageId == messageId)
    }

    public func batchUpdateMessageStatus(readMessageIds: [String], mentionMessageIds: [String]) {
        var readMessageIds = readMessageIds
        var readMessages: [Message] = []
        var mentionMessages: [Message] = []
        var conversationIds: Set<String> = []

        if readMessageIds.count > 0 {
            readMessages = MixinDatabase.shared.getCodables(condition: Message.Properties.messageId.in(readMessageIds) && Message.Properties.status != MessageStatus.FAILED.rawValue && Message.Properties.status != MessageStatus.READ.rawValue)
            readMessageIds = readMessages.map { $0.messageId }

            conversationIds = Set<String>(readMessages.map { $0.conversationId })
        }

        if mentionMessageIds.count > 0 {
            mentionMessages = MixinDatabase.shared.getCodables(condition: Message.Properties.messageId.in(mentionMessageIds) && Message.Properties.status != MessageStatus.FAILED.rawValue)
        }

        MixinDatabase.shared.transaction { (database) in
            if readMessageIds.count > 0 {
                try database.update(table: Message.tableName, on: [Message.Properties.status], with: [MessageStatus.READ.rawValue], where: Message.Properties.messageId.in(readMessageIds))

                for conversationId in conversationIds {
                    try MessageDAO.shared.updateUnseenMessageCount(database: database, conversationId: conversationId)
                }
            }

            if mentionMessageIds.count > 0 {
                try database.update(maps: [(MessageMention.Properties.hasRead, true)], tableName: MessageMention.tableName, condition: MessageMention.Properties.messageId.in(mentionMessageIds))
            }
        }

        guard !isAppExtension else {
            return
        }

        for message in readMessages {
            let change = ConversationChange(conversationId: message.conversationId, action: .updateMessageStatus(messageId: message.messageId, newStatus: .READ))
            NotificationCenter.default.afterPostOnMain(name: .ConversationDidChange, object: change)
        }

        for message in mentionMessages {
            let change = ConversationChange(conversationId: message.conversationId, action: .updateMessageMentionStatus(messageId: message.messageId, newStatus: .MENTION_READ))
            NotificationCenter.default.afterPostOnMain(name: .ConversationDidChange, object: change)
        }

        NotificationCenter.default.post(name: MixinService.messageReadStatusDidChangeNotification, object: self)
        UNUserNotificationCenter.current().removeNotifications(withIdentifiers: readMessageIds)
        UNUserNotificationCenter.current().removeNotifications(withIdentifiers: mentionMessageIds)
    }

    @discardableResult
    public func updateMessageStatus(messageId: String, status: String, from: String, updateUnseen: Bool = false) -> Bool {
        guard let oldMessage: Message = MixinDatabase.shared.getCodable(condition: Message.Properties.messageId == messageId) else {
            return false
        }
        
        guard oldMessage.status != MessageStatus.FAILED.rawValue else {
            let error = MixinServicesError.badMessageData(id: messageId, status: status, from: from)
            reporter.report(error: error)
            return false
        }
        
        guard MessageStatus.getOrder(messageStatus: status) > MessageStatus.getOrder(messageStatus: oldMessage.status) else {
            return false
        }
        
        let conversationId = oldMessage.conversationId
        if updateUnseen {
            MixinDatabase.shared.transaction { (database) in
                try database.update(table: Message.tableName, on: [Message.Properties.status], with: [status], where: Message.Properties.messageId == messageId)
                try updateUnseenMessageCount(database: database, conversationId: conversationId)
            }
        } else {
            MixinDatabase.shared.update(maps: [(Message.Properties.status, status)], tableName: Message.tableName, condition: Message.Properties.messageId == messageId)
        }

        if !isAppExtension {
            let change = ConversationChange(conversationId: conversationId, action: .updateMessageStatus(messageId: messageId, newStatus: MessageStatus(rawValue: status) ?? .UNKNOWN))
            NotificationCenter.default.afterPostOnMain(name: .ConversationDidChange, object: change)
        }
        return true
    }
    
    public func updateUnseenMessageCount(database: Database, conversationId: String) throws {
        try database.prepareUpdateSQL(sql: Self.sqlUpdateUnseenMessageCount).execute(with: [conversationId, myUserId, conversationId])
    }
    
    @discardableResult
    public func updateMediaMessage(messageId: String, keyValues: [(PropertyConvertible, ColumnEncodable?)]) -> Bool {
        return MixinDatabase.shared.update(maps: keyValues, tableName: Message.tableName, condition: Message.Properties.messageId == messageId && Message.Properties.category != MessageCategory.MESSAGE_RECALL.rawValue)
    }
    
    public func updateMediaMessage(messageId: String, mediaUrl: String, status: MediaStatus, conversationId: String) {
        guard MixinDatabase.shared.update(maps: [(Message.Properties.mediaUrl, mediaUrl), (Message.Properties.mediaStatus, status.rawValue)], tableName: Message.tableName, condition: Message.Properties.messageId == messageId && Message.Properties.category != MessageCategory.MESSAGE_RECALL.rawValue) else {
            return
        }
        
        let change = ConversationChange(conversationId: conversationId, action: .updateMessage(messageId: messageId))
        NotificationCenter.default.afterPostOnMain(name: .ConversationDidChange, object: change)
    }
    
    public func updateMediaStatus(messageId: String, status: MediaStatus, conversationId: String) {
        let targetStatus = status
        updateMediaStatusQueue.async {
            MixinDatabase.shared.transaction { (database) in
                let oldStatus = try database.getValue(on: Message.Properties.mediaStatus.asColumnResult(), fromTable: Message.tableName, where: Message.Properties.messageId == messageId)

                guard oldStatus.type == .null || (oldStatus.stringValue != targetStatus.rawValue) else {
                    return
                }

                if (targetStatus == .PENDING || targetStatus == .CANCELED) && oldStatus.stringValue == MediaStatus.DONE.rawValue {
                    return
                }

                let updateStatment = try database.prepareUpdate(table: Message.tableName, on: [Message.Properties.mediaStatus]).where(Message.Properties.messageId == messageId && Message.Properties.category != MessageCategory.MESSAGE_RECALL.rawValue)
                try updateStatment.execute(with: [targetStatus.rawValue])
                guard updateStatment.changes ?? 0 > 0 else {
                    return
                }

                let change = ConversationChange(conversationId: conversationId, action: .updateMediaStatus(messageId: messageId, mediaStatus: targetStatus))
                NotificationCenter.default.postOnMain(name: .ConversationDidChange, object: change)
            }
        }
    }
    
    public func updateOldStickerMessages() {
        MixinDatabase.shared.transaction { (database) in
            guard try database.isColumnExist(tableName: Message.tableName, columnName: "album_id") else {
                return
            }
            try database.prepareUpdateSQL(sql: MessageDAO.sqlUpdateOldStickers).execute()
        }
    }
    
    public func getFullMessage(messageId: String) -> MessageItem? {
        return MixinDatabase.shared.getCodables(sql: MessageDAO.sqlQueryFullMessageById, values: [messageId]).first
    }
    
    public func getMessage(messageId: String) -> Message? {
        return MixinDatabase.shared.getCodable(condition: Message.Properties.messageId == messageId)
    }

    public func getMessage(messageId: String, userId: String) -> Message? {
        return MixinDatabase.shared.getCodable(condition: Message.Properties.messageId == messageId && Message.Properties.userId == userId)
    }
    
    public func firstUnreadMessage(conversationId: String) -> Message? {
        guard hasUnreadMessage(conversationId: conversationId) else {
            return nil
        }
        let myLastMessage: Message? = MixinDatabase.shared.getCodable(condition: Message.Properties.conversationId == conversationId && Message.Properties.userId == myUserId,
                                                                      orderBy: [Message.Properties.createdAt.asOrder(by: .descending)])
        let lastReadCondition: Condition
        if let myLastMessage = myLastMessage {
            lastReadCondition = Message.Properties.conversationId == conversationId
                && Message.Properties.category != MessageCategory.SYSTEM_CONVERSATION.rawValue
                && Message.Properties.status == MessageStatus.READ.rawValue
                && Message.Properties.userId != myUserId
                && Message.Properties.createdAt > myLastMessage.createdAt
        } else {
            lastReadCondition = Message.Properties.conversationId == conversationId
                && Message.Properties.category != MessageCategory.SYSTEM_CONVERSATION.rawValue
                && Message.Properties.status == MessageStatus.READ.rawValue
                && Message.Properties.userId != myUserId
        }
        let lastReadMessage: Message? = MixinDatabase.shared.getCodable(condition: lastReadCondition,
                                                                        orderBy: [Message.Properties.createdAt.asOrder(by: .descending)])
        let firstUnreadCondition: Condition
        if let lastReadMessage = lastReadMessage {
            firstUnreadCondition = Message.Properties.conversationId == conversationId
                && Message.Properties.status == MessageStatus.DELIVERED.rawValue
                && Message.Properties.userId != myUserId
                && Message.Properties.createdAt > lastReadMessage.createdAt
        } else if let myLastMessage = myLastMessage {
            firstUnreadCondition = Message.Properties.conversationId == conversationId
                && Message.Properties.status == MessageStatus.DELIVERED.rawValue
                && Message.Properties.userId != myUserId
                && Message.Properties.createdAt > myLastMessage.createdAt
        } else {
            firstUnreadCondition = Message.Properties.conversationId == conversationId
                && Message.Properties.status == MessageStatus.DELIVERED.rawValue
                && Message.Properties.userId != myUserId
        }
        return MixinDatabase.shared.getCodable(condition: firstUnreadCondition,
                                               orderBy: [Message.Properties.createdAt.asOrder(by: .ascending)])
    }
    
    public typealias MessagesResult = (messages: [MessageItem], didReachBegin: Bool, didReachEnd: Bool)
    public func getMessages(conversationId: String, aroundMessageId messageId: String, count: Int) -> MessagesResult? {
        guard let message = getFullMessage(messageId: messageId) else {
            return nil
        }
        let aboveCount = 10
        let belowCount = count - aboveCount
        let messagesAbove = getMessages(conversationId: conversationId, aboveMessage: message, count: aboveCount)
        let messagesBelow = getMessages(conversationId: conversationId, belowMessage: message, count: belowCount)
        var messages = [MessageItem]()
        messages.append(contentsOf: messagesAbove)
        messages.append(message)
        messages.append(contentsOf: messagesBelow)
        return (messages, messagesAbove.count < aboveCount, messagesBelow.count < belowCount)
    }
    
    public func getMessages(conversationId: String, aboveMessage location: MessageItem, count: Int) -> [MessageItem] {
        let rowId = MixinDatabase.shared.getRowId(tableName: Message.tableName,
                                                  condition: Message.Properties.messageId == location.messageId)
        let messages: [MessageItem] = MixinDatabase.shared.getCodables(sql: MessageDAO.sqlQueryFullMessageBeforeRowId,
                                                                       values: [conversationId, rowId, count])
        return messages.reversed()
    }
    
    public func getMessages(conversationId: String, belowMessage location: MessageItem, count: Int) -> [MessageItem] {
        let rowId = MixinDatabase.shared.getRowId(tableName: Message.tableName,
                                                  condition: Message.Properties.messageId == location.messageId)
        let messages: [MessageItem] = MixinDatabase.shared.getCodables(sql: MessageDAO.sqlQueryFullMessageAfterRowId,
                                                                       values: [conversationId, rowId, count])
        return messages
    }
    
    public func getMessages(conversationId: String, categoryIn categories: [MessageCategory], earlierThan location: MessageItem?, count: Int) -> [MessageItem] {
        let categories = categories.map({ $0.rawValue }).joined(separator: "', '")
        var sql = """
        \(Self.sqlQueryFullMessage)
        WHERE m.conversation_id = ? AND m.category in ('\(categories)')
        """
        if let location = location {
            let rowId = MixinDatabase.shared.getRowId(tableName: Message.tableName,
                                                      condition: Message.Properties.messageId == location.messageId)
            sql += " AND m.ROWID < \(rowId)"
        }
        sql += " ORDER BY m.created_at DESC LIMIT ?"
        let messages: [MessageItem] = MixinDatabase.shared.getCodables(sql: sql, values: [conversationId, count])
        return messages
    }
    
    public func getFirstNMessages(conversationId: String, count: Int) -> [MessageItem] {
        return MixinDatabase.shared.getCodables(sql: MessageDAO.sqlQueryFirstNMessages, values: [conversationId, count])
    }
    
    public func getLastNMessages(conversationId: String, count: Int) -> [MessageItem] {
        let messages: [MessageItem] =  MixinDatabase.shared.getCodables(sql: MessageDAO.sqlQueryLastNMessages, values: [conversationId, count])
        return messages.reversed()
    }
    
    public func getInvitationMessage(conversationId: String, inviteeUserId: String) -> Message? {
        let condition: Condition = Message.Properties.conversationId == conversationId
            && Message.Properties.category == MessageCategory.SYSTEM_CONVERSATION.rawValue
            && Message.Properties.action == SystemConversationAction.ADD.rawValue
            && Message.Properties.participantId == inviteeUserId
        let order = [Message.Properties.createdAt.asOrder(by: .ascending)]
        return MixinDatabase.shared.getCodable(condition: condition, orderBy: order)
    }
    
    public func getUnreadMessagesCount(conversationId: String) -> Int {
        guard let firstUnreadMessage = self.firstUnreadMessage(conversationId: conversationId) else {
            return 0
        }
        return MixinDatabase.shared.getCount(on: Message.Properties.messageId.count(),
                                             fromTable: Message.tableName,
                                             condition: Message.Properties.conversationId == conversationId && Message.Properties.createdAt >= firstUnreadMessage.createdAt)
    }
    
    public func getNonFailedMessage(messageId: String) -> MessageItem? {
        guard !messageId.isEmpty else {
            return nil
        }
        return MixinDatabase.shared.getCodables(sql: MessageDAO.sqlQueryQuoteMessageById, values: [messageId]).first
    }
    
    public func insertMessage(message: Message, messageSource: String) {
        var message = message
        
        let quotedMessage: MessageItem?
        if let id = message.quoteMessageId, let quoted = getNonFailedMessage(messageId: id) {
            message.quoteContent = try? JSONEncoder.default.encode(quoted)
            quotedMessage = quoted
        } else {
            quotedMessage = nil
        }
        
        MixinDatabase.shared.transaction { (db) in
            if let mention = MessageMention(message: message, quotedMessage: quotedMessage) {
                try db.insertOrReplace(objects: [mention], intoTable: MessageMention.tableName)
            }
            try insertMessage(database: db, message: message, messageSource: messageSource)
        }
    }
    
    public func insertMessage(database: Database, message: Message, messageSource: String) throws {
        if message.category.hasPrefix("SIGNAL_") {
            try database.insert(objects: message, intoTable: Message.tableName)
        } else {
            try database.insertOrReplace(objects: message, intoTable: Message.tableName)
        }
        if message.status != MessageStatus.FAILED.rawValue {
            try FTSMessageDAO.shared.insert(database: database,
                                            messageId: message.messageId,
                                            category: message.category)
        }
        try MessageDAO.shared.updateUnseenMessageCount(database: database, conversationId: message.conversationId)

        if isAppExtension {
			if AppGroupUserDefaults.isRunningInMainApp {
				DarwinNotificationManager.shared.notifyConversationDidChangeInMainApp()
			}
			if AppGroupUserDefaults.User.currentConversationId == message.conversationId {
				AppGroupUserDefaults.User.reloadConversation = true
			}
        } else {
            guard let newMessage: MessageItem = try database.prepareSelectSQL(on: MessageItem.Properties.all, sql: MessageDAO.sqlQueryFullMessageById, values: [message.messageId]).allObjects().first else {
                return
            }
            let userInfo: [String: Any] = [
                MessageDAO.UserInfoKey.conversationId: newMessage.conversationId,
                MessageDAO.UserInfoKey.message: newMessage,
                MessageDAO.UserInfoKey.messsageSource: messageSource
            ]
            performSynchronouslyOnMainThread {
                NotificationCenter.default.post(name: MessageDAO.didInsertMessageNotification, object: self, userInfo: userInfo)
            }
        }
    }
    
    public func recallMessage(message: Message) {
        let messageId = message.messageId
        ReceiveMessageService.shared.stopRecallMessage(messageId: messageId, category: message.category, conversationId: message.conversationId, mediaUrl: message.mediaUrl)
        
        let quoteMessageIds = MixinDatabase.shared.getStringValues(column: Message.Properties.messageId.asColumnResult(), tableName: Message.tableName, condition: Message.Properties.conversationId == message.conversationId &&  Message.Properties.quoteMessageId == messageId)
        MixinDatabase.shared.transaction { (database) in
            try MessageDAO.shared.recallMessage(database: database, messageId: message.messageId, conversationId: message.conversationId, category: message.category, status: message.status, quoteMessageIds: quoteMessageIds)
        }
    }
    
    public func recallMessage(database: Database, messageId: String, conversationId: String, category: String, status: String, quoteMessageIds: [String]) throws {
        if let category = MessageCategory(rawValue: category), MessageCategory.ftsAvailable.contains(category) {
            try FTSMessageDAO.shared.remove(database: database, messageId: messageId)
        }
        
        var values: [(PropertyConvertible, ColumnEncodable?)] = [
            (Message.Properties.category, MessageCategory.MESSAGE_RECALL.rawValue)
        ]
        
        if status == MessageStatus.UNKNOWN.rawValue || ["_TEXT", "_POST", "_LOCATION"].contains(where: category.hasSuffix(_:)) {
            values.append((Message.Properties.content, MixinDatabase.NullValue()))
            values.append((Message.Properties.quoteMessageId, MixinDatabase.NullValue()))
            values.append((Message.Properties.quoteContent, MixinDatabase.NullValue()))
        } else if category.hasSuffix("_IMAGE") ||
            category.hasSuffix("_VIDEO") ||
            category.hasSuffix("_LIVE") ||
            category.hasSuffix("_DATA") ||
            category.hasSuffix("_AUDIO") {
            values.append((Message.Properties.content, MixinDatabase.NullValue()))
            values.append((Message.Properties.mediaUrl, MixinDatabase.NullValue()))
            values.append((Message.Properties.mediaStatus, MixinDatabase.NullValue()))
            values.append((Message.Properties.mediaMimeType, MixinDatabase.NullValue()))
            values.append((Message.Properties.mediaSize, 0))
            values.append((Message.Properties.mediaDuration, 0))
            values.append((Message.Properties.mediaWidth, 0))
            values.append((Message.Properties.mediaHeight, 0))
            values.append((Message.Properties.thumbImage, MixinDatabase.NullValue()))
            values.append((Message.Properties.thumbUrl, MixinDatabase.NullValue()))
            values.append((Message.Properties.mediaKey, MixinDatabase.NullValue()))
            values.append((Message.Properties.mediaDigest, MixinDatabase.NullValue()))
            values.append((Message.Properties.mediaWaveform, MixinDatabase.NullValue()))
            values.append((Message.Properties.name, MixinDatabase.NullValue()))
        } else if category.hasSuffix("_STICKER") {
            values.append((Message.Properties.stickerId, MixinDatabase.NullValue()))
        } else if category.hasSuffix("_CONTACT") {
            values.append((Message.Properties.sharedUserId, MixinDatabase.NullValue()))
        }
        if status == MessageStatus.FAILED.rawValue {
            values.append((Message.Properties.status, MessageStatus.DELIVERED.rawValue))
        }
        
        try database.update(maps: values,
                            tableName: Message.tableName,
                            condition: Message.Properties.messageId == messageId)
        try database.delete(fromTable: MessageMention.tableName,
                            where: MessageMention.Properties.messageId == messageId)
        
        if status == MessageStatus.FAILED.rawValue {
            try MessageDAO.shared.updateUnseenMessageCount(database: database, conversationId: conversationId)
        }
        
        if quoteMessageIds.count > 0, let quoteMessage: MessageItem = try database.prepareSelectSQL(on: MessageItem.Properties.all, sql: MessageDAO.sqlQueryQuoteMessageById, values: [messageId]).allObjects().first, let data = try? JSONEncoder().encode(quoteMessage) {
            try database.update(maps: [(Message.Properties.quoteContent, data)], tableName: Message.tableName, condition: Message.Properties.messageId.in(quoteMessageIds))
        }
        
        let messageIds = quoteMessageIds + [messageId]
        for messageId in messageIds {
            let change = ConversationChange(conversationId: conversationId, action: .recallMessage(messageId: messageId))
            NotificationCenter.default.afterPostOnMain(name: .ConversationDidChange, object: change)
        }
    }
    
    @discardableResult
    public func deleteMessage(id: String) -> Bool {
        var deleteCount = 0
        MixinDatabase.shared.transaction { (db) in
            let delete = try db.prepareDelete(fromTable: Message.tableName).where(Message.Properties.messageId == id)
            try delete.execute()
            deleteCount = delete.changes ?? 0
            try db.delete(fromTable: MessageMention.tableName, where: MessageMention.Properties.messageId == id)
            try FTSMessageDAO.shared.remove(database: db, messageId: id)
        }
        return deleteCount > 0
    }
    
    public func hasSentMessage(inConversationOf conversationId: String) -> Bool {
        let myId = myUserId
        return MixinDatabase.shared.isExist(type: Message.self, condition: Message.Properties.conversationId == conversationId && Message.Properties.userId == myId)
    }
    
    public func hasUnreadMessage(conversationId: String) -> Bool {
        let condition: Condition = Message.Properties.conversationId == conversationId
            && Message.Properties.status == MessageStatus.DELIVERED.rawValue
            && Message.Properties.userId != myUserId
        return MixinDatabase.shared.isExist(type: Message.self, condition: condition)
    }
    
    public func hasMessage(id: String) -> Bool {
        return MixinDatabase.shared.isExist(type: Message.self, condition: Message.Properties.messageId == id)
    }
    
}

extension MessageDAO {
    
    public func updateMessageContentAndStatus(content: String, status: String, mention: MessageMention?, messageId: String, category: String, conversationId: String, messageSource: String) {
        updateRedecryptMessage(keys: [Message.Properties.content, Message.Properties.status],
                               values: [content, status],
                               mention: mention,
                               messageId: messageId,
                               category: category,
                               conversationId: conversationId,
                               messageSource: messageSource)
    }
    
    public func updateMediaMessage(mediaData: TransferAttachmentData, status: String, messageId: String, category: String, conversationId: String, mediaStatus: MediaStatus, messageSource: String) {
        updateRedecryptMessage(keys: [
            Message.Properties.content,
            Message.Properties.mediaMimeType,
            Message.Properties.mediaSize,
            Message.Properties.mediaDuration,
            Message.Properties.mediaWidth,
            Message.Properties.mediaHeight,
            Message.Properties.thumbImage,
            Message.Properties.mediaKey,
            Message.Properties.mediaDigest,
            Message.Properties.mediaStatus,
            Message.Properties.mediaWaveform,
            Message.Properties.name,
            Message.Properties.status
            ], values: [
                mediaData.attachmentId,
                mediaData.mimeType,
                mediaData.size,
                mediaData.duration,
                mediaData.width,
                mediaData.height,
                mediaData.thumbnail,
                mediaData.key,
                mediaData.digest,
                mediaStatus.rawValue,
                mediaData.waveform,
                mediaData.name,
                status
        ], messageId: messageId, category: category, conversationId: conversationId, messageSource: messageSource)
    }
    
    public func updateLiveMessage(liveData: TransferLiveData, status: String, messageId: String, category: String, conversationId: String, messageSource: String) {
        let keys = [
            Message.Properties.mediaWidth,
            Message.Properties.mediaHeight,
            Message.Properties.mediaUrl,
            Message.Properties.thumbUrl,
            Message.Properties.status
        ]
        let values: [ColumnEncodable] = [
            liveData.width,
            liveData.height,
            liveData.url,
            liveData.thumbUrl,
            status
        ]
        updateRedecryptMessage(keys: keys, values: values, messageId: messageId, category: category, conversationId: conversationId, messageSource: messageSource)
    }
    
    public func updateStickerMessage(stickerData: TransferStickerData, status: String, messageId: String, category: String, conversationId: String, messageSource: String) {
        updateRedecryptMessage(keys: [Message.Properties.stickerId, Message.Properties.status], values: [stickerData.stickerId, status], messageId: messageId, category: category, conversationId: conversationId, messageSource: messageSource)
    }
    
    public func updateContactMessage(transferData: TransferContactData, status: String, messageId: String, category: String, conversationId: String, messageSource: String) {
        updateRedecryptMessage(keys: [Message.Properties.sharedUserId, Message.Properties.status], values: [transferData.userId, status], messageId: messageId, category: category, conversationId: conversationId, messageSource: messageSource)
    }
    
}

extension MessageDAO {
    
    private func updateRedecryptMessage(keys: [PropertyConvertible], values: [ColumnEncodable?], mention: MessageMention? = nil, messageId: String, category: String, conversationId: String, messageSource: String) {
        var newMessage: MessageItem?
        MixinDatabase.shared.transaction { (database) in
            if let mention = mention {
                try database.insertOrReplace(objects: [mention], intoTable: MessageMention.tableName)
            }
            let updateStatment = try database.prepareUpdate(table: Message.tableName, on: keys).where(Message.Properties.messageId == messageId && Message.Properties.category != MessageCategory.MESSAGE_RECALL.rawValue)
            try updateStatment.execute(with: values)
            guard updateStatment.changes ?? 0 > 0 else {
                return
            }
            try FTSMessageDAO.shared.insert(database: database, messageId: messageId, category: category)
            try MessageDAO.shared.updateUnseenMessageCount(database: database, conversationId: conversationId)
            
            newMessage = try database.prepareSelectSQL(on: MessageItem.Properties.all, sql: MessageDAO.sqlQueryFullMessageById, values: [messageId]).allObjects().first
        }
        
        guard let message = newMessage else {
            return
        }
        
        let userInfo: [String: Any] = [
            MessageDAO.UserInfoKey.conversationId: message.conversationId,
            MessageDAO.UserInfoKey.message: message,
            MessageDAO.UserInfoKey.messsageSource: messageSource
        ]
        performSynchronouslyOnMainThread {
            NotificationCenter.default.post(name: MessageDAO.didRedecryptMessageNotification, object: self, userInfo: userInfo)
        }
    }
    
}
