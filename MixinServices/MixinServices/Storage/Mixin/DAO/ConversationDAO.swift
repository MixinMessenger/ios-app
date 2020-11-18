import WCDBSwift

public final class ConversationDAO {
    
    public static let shared = ConversationDAO()
    
    private static let sqlQueryColumns = """
    SELECT c.conversation_id as conversationId, c.owner_id as ownerId, c.icon_url as iconUrl,
    c.announcement as announcement, c.category as category, c.name as name, c.status as status,
    c.last_read_message_id as lastReadMessageId, c.unseen_message_count as unseenMessageCount,
    (SELECT COUNT(*) FROM message_mentions mm WHERE mm.conversation_id = c.conversation_id AND mm.has_read = 0) as unseenMentionCount,
    CASE WHEN c.category = 'CONTACT' THEN u1.mute_until ELSE c.mute_until END as muteUntil,
    c.code_url as codeUrl, c.pin_time as pinTime,
    m.content as content, m.category as contentType, m.created_at as createdAt,
    m.user_id as senderId, u.full_name as senderFullName, u1.identity_number as ownerIdentityNumber,
    u1.full_name as ownerFullName, u1.avatar_url as ownerAvatarUrl, u1.is_verified as ownerIsVerified,
    m.action as actionName, u2.full_name as participantFullName, u2.user_id as participantUserId, m.status as messageStatus, m.id as messageId, u1.app_id as appId,
    mm.mentions
    """
    private static let sqlQueryConversation = """
    \(sqlQueryColumns)
    FROM conversations c
    LEFT JOIN messages m ON c.last_message_id = m.id
    LEFT JOIN users u ON u.user_id = m.user_id
    LEFT JOIN users u2 ON u2.user_id = m.participant_id
    LEFT JOIN message_mentions mm ON m.id = mm.message_id
    INNER JOIN users u1 ON u1.user_id = c.owner_id
    WHERE c.category IS NOT NULL %@
    ORDER BY c.pin_time DESC, c.last_message_created_at DESC
    """
    private static let sqlQueryConversationByCoversationId = String(format: sqlQueryConversation, " AND c.conversation_id = ? ")
    private static let sqlQueryGroupOrStrangerConversationByName = String(format: sqlQueryConversation, " AND ((c.category = 'GROUP' AND c.name LIKE ? ESCAPE '/') OR (c.category = 'CONTACT' AND u1.relationship = 'STRANGER' AND u1.full_name LIKE ? ESCAPE '/'))")
    private static let sqlQueryStorageUsage = """
    SELECT c.conversation_id as conversationId, c.owner_id as ownerId, c.category, c.icon_url as iconUrl, c.name, u.identity_number as ownerIdentityNumber,
    u.full_name as ownerFullName, u.avatar_url as ownerAvatarUrl, u.is_verified as ownerIsVerified, m.mediaSize
    FROM conversations c
    INNER JOIN (SELECT conversation_id, sum(media_size) as mediaSize FROM messages WHERE media_status = 'DONE' GROUP BY conversation_id) m
        ON m.conversation_id = c.conversation_id
    INNER JOIN users u ON u.user_id = c.owner_id
    ORDER BY m.mediaSize DESC
    """
    private static let sqlQueryConversationStorageUsage = """
    SELECT category, sum(media_size) as mediaSize, count(id) as messageCount  FROM messages
    WHERE conversation_id = ? AND media_status = 'DONE' GROUP BY category
    """
    private static let sqlUnreadMessageCountWithoutMuted = """
    SELECT ifnull(SUM(unseen_message_count),0) FROM (
        SELECT c.unseen_message_count, CASE WHEN c.category = 'CONTACT' THEN u.mute_until ELSE c.mute_until END as muteUntil
        FROM conversations c
        INNER JOIN users u ON u.user_id = c.owner_id
        WHERE muteUntil < ?
    )
    """
    
    public func hasUnreadMessage(outsideCircleWith id: String) -> Bool {
        let sql = """
            SELECT 1 FROM conversations
            WHERE conversation_id NOT IN (
                SELECT conversation_id FROM circle_conversations WHERE circle_id = ?
            ) AND unseen_message_count > 0
            LIMIT 1
        """
        let value = MixinDatabase.shared.scalar(sql: sql, values: [id])
        return value.int64Value > 0
    }
    
    public func getUnreadMessageCount() -> Int {
        let sql = "SELECT ifnull(SUM(unseen_message_count),0) FROM conversations WHERE category IS NOT NULL"
        let value = MixinDatabase.shared.scalar(sql: sql)
        return Int(value.int64Value)
    }
    
    public func getUnreadMessageCountWithoutMuted() -> Int {
        let value = MixinDatabase.shared.scalar(sql: ConversationDAO.sqlUnreadMessageCountWithoutMuted, values: [Date().toUTCString()]).int64Value
        return Int(value)
    }
    
    public func getCategoryStorages(conversationId: String) -> [ConversationCategoryStorage] {
        return MixinDatabase.shared.getCodables(sql: ConversationDAO.sqlQueryConversationStorageUsage, values: [conversationId])
    }
    
    public func storageUsageConversations() -> [ConversationStorageUsage] {
        return MixinDatabase.shared.getCodables(sql: ConversationDAO.sqlQueryStorageUsage)
    }
    
    public func isExist(conversationId: String) -> Bool {
        return MixinDatabase.shared.isExist(type: Conversation.self, condition: Conversation.Properties.conversationId == conversationId)
    }
    
    public func hasValidConversation() -> Bool {
        return MixinDatabase.shared.isExist(type: Conversation.self, condition: Conversation.Properties.status != ConversationStatus.QUIT.rawValue)
    }
    
    public func updateCodeUrl(conversation: ConversationResponse) {
        MixinDatabase.shared.update(maps: [(Conversation.Properties.codeUrl, conversation.codeUrl)], tableName: Conversation.tableName, condition: Conversation.Properties.conversationId == conversation.conversationId)
        NotificationCenter.default.afterPostOnMain(name: .ConversationDidChange, object: ConversationChange(conversationId: conversation.conversationId, action: .updateConversation(conversation: conversation)))
    }
    
    public func getConversationIconUrl(conversationId: String) -> String? {
        return MixinDatabase.shared.scalar(on: Conversation.Properties.iconUrl, fromTable: Conversation.tableName, condition: Conversation.Properties.conversationId == conversationId)?.stringValue
    }
    
    public func updateIconUrl(conversationId: String, iconUrl: String) {
        MixinDatabase.shared.update(maps: [(Conversation.Properties.iconUrl, iconUrl)], tableName: Conversation.tableName, condition: Conversation.Properties.conversationId == conversationId)
    }
    
    public func getStartStatusConversations() -> [String] {
        return MixinDatabase.shared.getStringValues(column: Conversation.Properties.conversationId, tableName: Conversation.tableName, condition: Conversation.Properties.status == ConversationStatus.START.rawValue)
    }
    
    public func updateConversationOwnerId(conversationId: String, ownerId: String) -> Bool {
        return MixinDatabase.shared.update(maps: [(Conversation.Properties.ownerId, ownerId)], tableName: Conversation.tableName, condition: Conversation.Properties.conversationId == conversationId)
    }
    
    public func updateConversationMuteUntil(conversationId: String, muteUntil: String) {
        MixinDatabase.shared.update(maps: [(Conversation.Properties.muteUntil, muteUntil)], tableName: Conversation.tableName, condition: Conversation.Properties.conversationId == conversationId)
        guard let conversation = getConversation(conversationId: conversationId) else {
            return
        }
        let change = ConversationChange(conversationId: conversationId, action: .update(conversation: conversation))
        NotificationCenter.default.afterPostOnMain(name: .ConversationDidChange, object: change)
    }
    
    public func updateConversation(with conversationId: String, inCirleOf circleId: String?, pinTime: String?) {
        let pinTime: ColumnEncodable = pinTime ?? MixinDatabase.NullValue()
        if let circleId = circleId {
            let condition = CircleConversation.Properties.circleId == circleId
                && CircleConversation.Properties.conversationId == conversationId
            MixinDatabase.shared.update(maps: [(CircleConversation.Properties.pinTime, pinTime)],
                                        tableName: CircleConversation.tableName,
                                        condition: condition)
        } else {
            MixinDatabase.shared.update(maps: [(Conversation.Properties.pinTime, pinTime)],
                                        tableName: Conversation.tableName,
                                        condition: Conversation.Properties.conversationId == conversationId)
        }
    }
    
    public func exitGroup(conversationId: String) {
        MixinDatabase.shared.transaction { (db) in
            try db.update(table: Conversation.tableName,
                on: [Conversation.Properties.unseenMessageCount, Conversation.Properties.status],
                with: [0, ConversationStatus.QUIT.rawValue],
                where: Conversation.Properties.conversationId == conversationId)
            try db.delete(fromTable: ParticipantSession.tableName, where: ParticipantSession.Properties.conversationId == conversationId)
            try db.delete(fromTable: Participant.tableName, where: Participant.Properties.conversationId == conversationId)
        }
        let change = ConversationChange(conversationId: conversationId, action: .updateConversationStatus(status: .QUIT))
        NotificationCenter.default.afterPostOnMain(name: .ConversationDidChange, object: change)
        NotificationCenter.default.afterPostOnMain(name: .ParticipantDidChange, object: conversationId)
    }

    public func deleteChat(conversationId: String) {
        let mediaUrls = MessageDAO.shared.getMediaUrls(conversationId: conversationId, categories: MessageCategory.allMediaCategories)

        MixinDatabase.shared.transaction { (db) in
            try db.delete(fromTable: Message.tableName, where: Message.Properties.conversationId == conversationId)
            try db.delete(fromTable: FTSMessage.tableName, where: FTSMessage.Properties.conversationId == conversationId)
            try db.delete(fromTable: MessageMention.tableName, where: MessageMention.Properties.conversationId == conversationId)
            try db.delete(fromTable: Conversation.tableName, where: Conversation.Properties.conversationId == conversationId)
            try db.delete(fromTable: Participant.tableName, where: Participant.Properties.conversationId == conversationId)
            try db.delete(fromTable: ParticipantSession.tableName, where: ParticipantSession.Properties.conversationId == conversationId)
        }

        ConcurrentJobQueue.shared.addJob(job: AttachmentCleanUpJob(conversationId: conversationId, mediaUrls: mediaUrls))

        NotificationCenter.default.afterPostOnMain(name: .ConversationDidChange)
    }

    public func clearChat(conversationId: String) {
        let mediaUrls = MessageDAO.shared.getMediaUrls(conversationId: conversationId, categories: MessageCategory.allMediaCategories)

        MixinDatabase.shared.transaction { (db) in
            try db.delete(fromTable: Message.tableName, where: Message.Properties.conversationId == conversationId)
            try db.delete(fromTable: FTSMessage.tableName, where: FTSMessage.Properties.conversationId == conversationId)
            try db.delete(fromTable: MessageMention.tableName, where: MessageMention.Properties.conversationId == conversationId)
            try db.update(table: Conversation.tableName,
                on: [Conversation.Properties.unseenMessageCount],
                with: [0],
                where: Conversation.Properties.conversationId == conversationId)
        }

        ConcurrentJobQueue.shared.addJob(job: AttachmentCleanUpJob(conversationId: conversationId, mediaUrls: mediaUrls))

        let change = ConversationChange(conversationId: conversationId, action: .reload)
        NotificationCenter.default.afterPostOnMain(name: .ConversationDidChange, object: change)
    }
    
    public func getConversation(conversationId: String) -> ConversationItem? {
        guard !conversationId.isEmpty else {
            return nil
        }
        return MixinDatabase.shared.getCodables(sql: ConversationDAO.sqlQueryConversationByCoversationId, values: [conversationId]).first
    }
    
    public func getGroupOrStrangerConversation(withNameLike keyword: String, limit: Int?) -> [ConversationItem] {
        var sql = ConversationDAO.sqlQueryGroupOrStrangerConversationByName
        if let limit = limit {
            sql += " LIMIT \(limit)"
        }
        let keyword = "%\(keyword.sqlEscaped)%"
        return MixinDatabase.shared.getCodables(sql: sql, values: [keyword, keyword])
    }
    
    public func getOriginalConversation(conversationId: String) -> Conversation? {
        return MixinDatabase.shared.getCodable(condition: Conversation.Properties.conversationId == conversationId)
    }
    
    public func getConversationStatus(conversationId: String) -> Int? {
        guard let result = MixinDatabase.shared.scalar(on: Conversation.Properties.status, fromTable: Conversation.tableName, condition: Conversation.Properties.conversationId == conversationId)?.int32Value else {
            return nil
        }
        return Int(result)
    }
    
    public func getConversationCategory(conversationId: String) -> String? {
        return MixinDatabase.shared.scalar(on: Conversation.Properties.category, fromTable: Conversation.tableName, condition: Conversation.Properties.conversationId == conversationId)?.stringValue
    }
    
    public func conversationList(limit: Int? = nil, circleId: String? = nil) -> [ConversationItem] {
        var sql: String
        if circleId == nil {
            sql = String(format: Self.sqlQueryConversation, "")
        } else {
            sql = """
                SELECT c.conversation_id as conversationId, c.owner_id as ownerId, c.icon_url as iconUrl,
                c.announcement as announcement, c.category as category, c.name as name, c.status as status,
                c.last_read_message_id as lastReadMessageId, c.unseen_message_count as unseenMessageCount,
                (SELECT COUNT(*) FROM message_mentions mm WHERE mm.conversation_id = c.conversation_id AND mm.has_read = 0) as unseenMentionCount,
                CASE WHEN c.category = 'CONTACT' THEN u1.mute_until ELSE c.mute_until END as muteUntil,
                c.code_url as codeUrl, cc.pin_time as pinTime,
                m.content as content, m.category as contentType, m.created_at as createdAt,
                m.user_id as senderId, u.full_name as senderFullName, u1.identity_number as ownerIdentityNumber,
                u1.full_name as ownerFullName, u1.avatar_url as ownerAvatarUrl, u1.is_verified as ownerIsVerified,
                m.action as actionName, u2.full_name as participantFullName, u2.user_id as participantUserId,
                m.status as messageStatus, m.id as messageId, u1.app_id as appId,
                mm.mentions
                FROM conversations c
                LEFT JOIN messages m ON c.last_message_id = m.id
                LEFT JOIN users u ON u.user_id = m.user_id
                LEFT JOIN users u2 ON u2.user_id = m.participant_id
                LEFT JOIN message_mentions mm ON m.id = mm.message_id
                INNER JOIN users u1 ON u1.user_id = c.owner_id
                INNER JOIN circle_conversations cc ON cc.conversation_id = c.conversation_id
                WHERE c.category IS NOT NULL AND cc.circle_id = ?
                ORDER BY cc.pin_time DESC, c.last_message_created_at DESC
            """
        }
        if let limit = limit {
            sql = sql + " LIMIT \(limit)"
        }
        if let id = circleId {
            return MixinDatabase.shared.getCodables(sql: sql, values: [id])
        } else {
            return MixinDatabase.shared.getCodables(sql: sql)
        }
    }
    
    public func createPlaceConversation(conversationId: String, ownerId: String) {
        guard !conversationId.isEmpty else {
            return
        }
        guard !MixinDatabase.shared.isExist(type: Conversation.self, condition: Conversation.Properties.conversationId == conversationId) else {
            return
        }
        let conversation = Conversation.createConversation(conversationId: conversationId, category: nil, recipientId: ownerId, status: ConversationStatus.START.rawValue)
        MixinDatabase.shared.insert(objects: [conversation])
    }
    
    public func createConversation(conversationId: String, name: String, members: [GroupUser]) -> Bool {
        let createdAt = Date().toUTCString()
        let conversation = Conversation(conversationId: conversationId, ownerId: myUserId, category: ConversationCategory.GROUP.rawValue, name: name, iconUrl: nil, announcement: nil, lastMessageId: nil, lastMessageCreatedAt: createdAt, lastReadMessageId: nil, unseenMessageCount: 0, status: ConversationStatus.START.rawValue, draft: nil, muteUntil: nil, codeUrl: nil, pinTime: nil)
        var participants = members.map { Participant(conversationId: conversationId, userId: $0.userId, role: "", status: ParticipantStatus.SUCCESS.rawValue, createdAt: createdAt) }
        participants.append(Participant(conversationId: conversationId, userId: myUserId, role: ParticipantRole.OWNER.rawValue, status: ParticipantStatus.SUCCESS.rawValue, createdAt: createdAt))
        
        return MixinDatabase.shared.transaction { (db) in
            try db.insert(objects: conversation, intoTable: Conversation.tableName)
            try db.insertOrReplace(objects: participants, intoTable: Participant.tableName)
        }
    }
    
    public func createNewConversation(response: ConversationResponse) -> (ConversationItem, [ParticipantUser]) {
        let conversationId = response.conversationId
        var conversation: ConversationItem!
        var participantUsers = [ParticipantUser]()
        
        MixinDatabase.shared.transaction { (db) in
            try db.insert(objects: Conversation.createConversation(from: response, ownerId: myUserId, status: .SUCCESS), intoTable: Conversation.tableName)
            
            let participants = response.participants.map { Participant(conversationId: conversationId, userId: $0.userId, role: $0.role, status: ParticipantStatus.SUCCESS.rawValue, createdAt: $0.createdAt) }
            try db.insert(objects: participants, intoTable: Participant.tableName)
            
            conversation = try db.prepareSelectSQL(on: ConversationItem.Properties.all, sql: ConversationDAO.sqlQueryConversationByCoversationId, values: [conversationId]).allObjects().first
            participantUsers = try db.prepareSelectSQL(on: ParticipantUser.Properties.all, sql: ParticipantDAO.sqlQueryGroupIconParticipants, values: [conversationId]).allObjects()
        }
        
        return (conversation, participantUsers)
    }

    @discardableResult
    public func createConversation(conversation: ConversationResponse, targetStatus: ConversationStatus) -> ConversationItem? {
        var ownerId = conversation.creatorId
        if conversation.category == ConversationCategory.CONTACT.rawValue {
            if let ownerParticipant = conversation.participants.first(where: { (participant) -> Bool in
                return participant.userId != myUserId
            }) {
                ownerId = ownerParticipant.userId
            }
        }

        let conversationId = conversation.conversationId
        var resultConversation: ConversationItem?
        MixinDatabase.shared.transaction { (db) in
            let oldStatus = try db.getValue(on: Conversation.Properties.status.asColumnResult(), fromTable: Conversation.tableName, where: Conversation.Properties.conversationId == conversationId)

            guard oldStatus.type == .null || (oldStatus.int32Value != targetStatus.rawValue) else {
                return
            }

            if oldStatus.type == .null {
                let targetConversation = Conversation.createConversation(from: conversation, ownerId: ownerId, status: targetStatus)
                try db.insert(objects: targetConversation, intoTable: Conversation.tableName)
            } else {
                try db.update(table: Conversation.tableName, on: [Conversation.Properties.ownerId, Conversation.Properties.category, Conversation.Properties.name, Conversation.Properties.announcement, Conversation.Properties.status, Conversation.Properties.muteUntil, Conversation.Properties.codeUrl], with: [ownerId, conversation.category, conversation.name, conversation.announcement, targetStatus.rawValue, conversation.muteUntil, conversation.codeUrl], where: Conversation.Properties.conversationId == conversationId)
            }
            
            if conversation.participants.count > 0 {
                let participants = conversation.participants.map { Participant(conversationId: conversationId, userId: $0.userId, role: $0.role, status: ParticipantStatus.START.rawValue, createdAt: $0.createdAt) }
                try db.insertOrReplace(objects: participants, intoTable: Participant.tableName)
                
                if conversation.category == ConversationCategory.GROUP.rawValue {
                    let creatorId = conversation.creatorId
                    if !conversation.participants.contains(where: { $0.userId == creatorId }) {
                        ConcurrentJobQueue.shared.addJob(job: RefreshUserJob(userIds: [creatorId]))
                    }
                }
            }
            
            if let participantSessions = conversation.participantSessions, participantSessions.count > 0 {
                let sessionParticipants = participantSessions.map {
                    ParticipantSession(conversationId: conversationId, userId: $0.userId, sessionId: $0.sessionId, sentToServer: nil, createdAt: Date().toUTCString())
                }
                try db.insertOrReplace(objects: sessionParticipants, intoTable: ParticipantSession.tableName)
            }
            
            let statment = try db.prepareUpdateSQL(sql: ParticipantDAO.sqlUpdateStatus)
            try statment.execute(with: [conversationId])
            
            let userIds = try ParticipantDAO.shared.getNeedSyncParticipantIds(database: db, conversationId: conversationId)
            if userIds.count > 0 {
                ConcurrentJobQueue.shared.addJob(job: RefreshUserJob(userIds: userIds))
            }

            resultConversation = try db.prepareSelectSQL(on: ConversationItem.Properties.all, sql: ConversationDAO.sqlQueryConversationByCoversationId, values: [conversationId]).allObjects().first
            
            NotificationCenter.default.afterPostOnMain(name: .ConversationDidChange, object: ConversationChange(conversationId: conversationId, action: .updateConversation(conversation: conversation)))
        }
        return resultConversation
    }
    
    public func updateConversation(conversation: ConversationResponse) {
        let conversationId = conversation.conversationId
        var ownerId = conversation.creatorId
        if conversation.category == ConversationCategory.CONTACT.rawValue {
            if let ownerParticipant = conversation.participants.first(where: { (participant) -> Bool in
                return participant.userId != myUserId
            }) {
                ownerId = ownerParticipant.userId
            }
        }
        guard let oldConversation: Conversation = MixinDatabase.shared.getCodable(condition: Conversation.Properties.conversationId == conversationId) else {
            return
        }
        
        if oldConversation.announcement != conversation.announcement, !conversation.announcement.isEmpty {
            AppGroupUserDefaults.User.hasUnreadAnnouncement[conversationId] = true
        }
        
        MixinDatabase.shared.transaction { (db) in
            try db.delete(fromTable: Participant.tableName, where: Participant.Properties.conversationId == conversationId)
            let participants = conversation.participants.map { Participant(conversationId: conversationId, userId: $0.userId, role: $0.role, status: ParticipantStatus.START.rawValue, createdAt: $0.createdAt) }
            try db.insertOrReplace(objects: participants, intoTable: Participant.tableName)
            
            try ParticipantSessionDAO.shared.syncConversationParticipantSession(conversation: conversation, db: db)
            
            let statment = try db.prepareUpdateSQL(sql: ParticipantDAO.sqlUpdateStatus)
            try statment.execute(with: [conversationId])
            
            try db.update(table: Conversation.tableName, on: [Conversation.Properties.ownerId, Conversation.Properties.category, Conversation.Properties.name, Conversation.Properties.announcement, Conversation.Properties.status, Conversation.Properties.muteUntil, Conversation.Properties.codeUrl], with: [ownerId, conversation.category, conversation.name, conversation.announcement, ConversationStatus.SUCCESS.rawValue, conversation.muteUntil, conversation.codeUrl], where: Conversation.Properties.conversationId == conversationId)
            
            let userIds = try ParticipantDAO.shared.getNeedSyncParticipantIds(database: db, conversationId: conversationId)
            if userIds.count > 0 {
                ConcurrentJobQueue.shared.addJob(job: RefreshUserJob(userIds: userIds))
            }

            if oldConversation.status != ConversationStatus.SUCCESS.rawValue {
                let change = ConversationChange(conversationId: conversationId, action: .updateConversationStatus(status: .SUCCESS))
                NotificationCenter.default.afterPostOnMain(name: .ConversationDidChange, object: change)
            }
            NotificationCenter.default.afterPostOnMain(name: .ConversationDidChange, object: ConversationChange(conversationId: conversationId, action: .updateConversation(conversation: conversation)))
        }
    }
    
    public func makeConversationId(userId: String, ownerUserId: String) -> String {
        return (min(userId, ownerUserId) + max(userId, ownerUserId)).toUUID()
    }
    
}
