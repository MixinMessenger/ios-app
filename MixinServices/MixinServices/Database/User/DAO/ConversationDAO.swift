import GRDB

public final class ConversationDAO: UserDatabaseDAO {
    
    public static let shared = ConversationDAO()
    
    public static let willClearConversationNotification = Notification.Name("one.mixin.service.ConversationDAO.willClearConversation")
    public static let conversationIdUserInfoKey = "cid"
    
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
    ORDER BY %@c.pin_time DESC, c.last_message_created_at DESC
    """
    private static let sqlQueryConversationByCoversationId = String(format: sqlQueryConversation, " AND c.conversation_id = ? ", "")
    
    public func hasUnreadMessage(outsideCircleWith id: String) -> Bool {
        let sql = """
            SELECT 1 FROM conversations
            WHERE conversation_id NOT IN (
                SELECT conversation_id FROM circle_conversations WHERE circle_id = ?
            ) AND unseen_message_count > 0
            LIMIT 1
        """
        let value: Int64 = db.select(with: sql, arguments: [id]) ?? 0
        return value > 0
    }
    
    public func getUnreadMessageCount() -> Int {
        let sql = "SELECT ifnull(SUM(unseen_message_count),0) FROM conversations WHERE category IS NOT NULL"
        return db.select(with: sql) ?? 0
    }
    
    public func getUnreadMessageCountWithoutMuted() -> Int {
        let sql = """
        SELECT ifnull(SUM(unseen_message_count),0) FROM (
            SELECT c.unseen_message_count, CASE WHEN c.category = 'CONTACT' THEN u.mute_until ELSE c.mute_until END as muteUntil
            FROM conversations c
            INNER JOIN users u ON u.user_id = c.owner_id
            WHERE muteUntil < ?
        )
        """
        return db.select(with: sql, arguments: [Date().toUTCString()]) ?? 0
    }
    
    public func getCategoryStorages(conversationId: String) -> [ConversationCategoryStorage] {
        let sql = """
        SELECT category, sum(media_size) as mediaSize, count(id) as messageCount FROM messages
        WHERE conversation_id = ? AND media_status = 'DONE' GROUP BY category
        """
        return db.select(with: sql, arguments: [conversationId])
    }
    
    public func storageUsageConversations() -> [ConversationStorageUsage] {
        let sql = """
        SELECT c.conversation_id as conversationId, c.owner_id as ownerId, c.category, c.icon_url as iconUrl, c.name, u.identity_number as ownerIdentityNumber,
        u.full_name as ownerFullName, u.avatar_url as ownerAvatarUrl, u.is_verified as ownerIsVerified, m.mediaSize
        FROM conversations c
        INNER JOIN (SELECT conversation_id, sum(media_size) as mediaSize FROM messages WHERE media_status = 'DONE' GROUP BY conversation_id) m
            ON m.conversation_id = c.conversation_id
        INNER JOIN users u ON u.user_id = c.owner_id
        ORDER BY m.mediaSize DESC
        """
        return db.select(with: sql)
    }
    
    public func isExist(conversationId: String) -> Bool {
        db.recordExists(in: Conversation.self,
                        where: Conversation.column(of: .conversationId) == conversationId)
    }
    
    public func updateCodeUrl(conversation: ConversationResponse) {
        db.update(Conversation.self,
                  assignments: [Conversation.column(of: .codeUrl).set(to: conversation.codeUrl)],
                  where: Conversation.column(of: .conversationId) == conversation.conversationId) { _ in
            let change = ConversationChange(conversationId: conversation.conversationId,
                                            action: .updateConversation(conversation: conversation))
            NotificationCenter.default.post(onMainThread: conversationDidChangeNotification, object: change)
        }
    }
    
    public func getConversationIconUrl(conversationId: String) -> String? {
        return db.select(column: Conversation.column(of: .iconUrl),
                         from: Conversation.self,
                         where: Conversation.column(of: .conversationId) == conversationId)
    }
    
    public func updateIconUrl(conversationId: String, iconUrl: String) {
        db.update(Conversation.self,
                  assignments: [Conversation.column(of: .iconUrl).set(to: iconUrl)],
                  where: Conversation.column(of: .conversationId) == conversationId)
    }
    
    public func getStartStatusConversations() -> [String] {
        return db.select(column: Conversation.column(of: .conversationId),
                         from: Conversation.self,
                         where: Conversation.column(of: .status) == ConversationStatus.START.rawValue)
    }
    
    public func updateConversationOwnerId(conversationId: String, ownerId: String) -> Bool {
        db.update(Conversation.self,
                  assignments: [Conversation.column(of: .ownerId).set(to: ownerId)],
                  where: Conversation.column(of: .conversationId) == conversationId)
    }
    
    public func updateConversationMuteUntil(conversationId: String, muteUntil: String) {
        db.update(Conversation.self,
                  assignments: [Conversation.column(of: .muteUntil).set(to: muteUntil)],
                  where: Conversation.column(of: .conversationId) == conversationId) { _ in
            guard let conversation = self.getConversation(conversationId: conversationId) else {
                return
            }
            let change = ConversationChange(conversationId: conversationId,
                                            action: .update(conversation: conversation))
            NotificationCenter.default.post(onMainThread: conversationDidChangeNotification, object: change)
        }
    }
    
    public func updateConversation(with conversationId: String, inCirleOf circleId: String?, pinTime: String?) {
        if let circleId = circleId {
            let condition = CircleConversation.column(of: .circleId) == circleId
                && CircleConversation.column(of: .conversationId) == conversationId
            db.update(CircleConversation.self,
                      assignments: [CircleConversation.column(of: .pinTime).set(to: pinTime)],
                      where: condition)
        } else {
            db.update(Conversation.self,
                      assignments: [Conversation.column(of: .pinTime).set(to: pinTime)],
                      where: Conversation.column(of: .conversationId) == conversationId)
        }
    }
    
    public func exitGroup(conversationId: String) {
        db.write { db in
            let assignments = [
                Conversation.column(of: .unseenMessageCount).set(to: 0),
                Conversation.column(of: .status).set(to: ConversationStatus.QUIT.rawValue)
            ]
            try Conversation
                .filter(Conversation.column(of: .conversationId) == conversationId)
                .updateAll(db, assignments)
            try ParticipantSession
                .filter(ParticipantSession.column(of: .conversationId) == conversationId)
                .deleteAll(db)
            try Participant
                .filter(Participant.column(of: .conversationId) == conversationId)
                .deleteAll(db)
            try deleteFTSContent(with: conversationId, from: db)
            db.afterNextTransactionCommit { (_) in
                NotificationCenter.default.post(onMainThread: ParticipantDAO.participantDidChangeNotification,
                                                object: self,
                                                userInfo: [ParticipantDAO.UserInfoKey.conversationId: conversationId])
                let change = ConversationChange(conversationId: conversationId,
                                                action: .updateConversationStatus(status: .QUIT))
                NotificationCenter.default.post(onMainThread: conversationDidChangeNotification, object: change)
            }
        }
    }
    
    public func deleteChat(conversationId: String) {
        let mediaUrls = MessageDAO.shared.getMediaUrls(conversationId: conversationId, categories: MessageCategory.allMediaCategories)
        db.write { db in
            let deletedTranscriptIds = try deleteTranscriptChildrenReferenced(by: conversationId, from: db)
            try Message
                .filter(Message.column(of: .conversationId) == conversationId)
                .deleteAll(db)
            try MessageMention
                .filter(MessageMention.column(of: .conversationId) == conversationId)
                .deleteAll(db)
            try Conversation
                .filter(Conversation.column(of: .conversationId) == conversationId)
                .deleteAll(db)
            try Participant
                .filter(Participant.column(of: .conversationId) == conversationId)
                .deleteAll(db)
            try ParticipantSession
                .filter(ParticipantSession.column(of: .conversationId) == conversationId)
                .deleteAll(db)
            try deleteFTSContent(with: conversationId, from: db)
            db.afterNextTransactionCommit { (_) in
                let job = AttachmentCleanUpJob(conversationId: conversationId,
                                               mediaUrls: mediaUrls,
                                               transcriptIds: deletedTranscriptIds)
                ConcurrentJobQueue.shared.addJob(job: job)
                NotificationCenter.default.post(onMainThread: conversationDidChangeNotification, object: nil)
            }
        }
    }
    
    public func clearChat(conversationId: String) {
        let mediaUrls = MessageDAO.shared.getMediaUrls(conversationId: conversationId, categories: MessageCategory.allMediaCategories)
        db.write { db in
            let deletedTranscriptIds = try deleteTranscriptChildrenReferenced(by: conversationId, from: db)
            NotificationCenter.default.post(onMainThread: Self.willClearConversationNotification,
                                            object: self,
                                            userInfo: [Self.conversationIdUserInfoKey: conversationId])
            try Message
                .filter(Message.column(of: .conversationId) == conversationId)
                .deleteAll(db)
            try MessageMention
                .filter(MessageMention.column(of: .conversationId) == conversationId)
                .deleteAll(db)
            try Conversation
                .filter(Conversation.column(of: .conversationId) == conversationId)
                .updateAll(db, [Conversation.column(of: .unseenMessageCount).set(to: 0)])
            try deleteFTSContent(with: conversationId, from: db)
            db.afterNextTransactionCommit { (_) in
                let job = AttachmentCleanUpJob(conversationId: conversationId,
                                               mediaUrls: mediaUrls,
                                               transcriptIds: deletedTranscriptIds)
                ConcurrentJobQueue.shared.addJob(job: job)
                let change = ConversationChange(conversationId: conversationId, action: .reload)
                NotificationCenter.default.post(onMainThread: conversationDidChangeNotification, object: change)
            }
        }
    }
    
    public func getConversation(conversationId: String) -> ConversationItem? {
        guard !conversationId.isEmpty else {
            return nil
        }
        return db.select(with: ConversationDAO.sqlQueryConversationByCoversationId,
                         arguments: [conversationId])
    }
    
    public func getGroupOrStrangerConversation(withNameLike keyword: String, limit: Int?) -> [ConversationItem] {
        let condition = "AND ((c.category = 'GROUP' AND c.name LIKE :wildcarded ESCAPE '/') OR (c.category = 'CONTACT' AND u1.relationship = 'STRANGER' AND u1.full_name LIKE :wildcarded ESCAPE '/'))"
        let order = "CASE WHEN ((c.category = 'GROUP' AND LOWER(c.name) = :lowercased) OR (c.category = 'CONTACT' AND LOWER(u1.full_name) = :lowercased)) THEN 1 ELSE 0 END DESC, "
        var sql = String(format: Self.sqlQueryConversation, condition, order)
        if let limit = limit {
            sql += " LIMIT \(limit)"
        }
        let arguments = ["wildcarded": "%\(keyword.sqlEscaped)%", "lowercased": keyword.lowercased()]
        return db.select(with: sql, arguments: StatementArguments(arguments))
    }
    
    public func getConversationStatus(conversationId: String) -> Int? {
        db.select(column: Conversation.column(of: .status),
                  from: Conversation.self,
                  where: Conversation.column(of: .conversationId) == conversationId)
    }
    
    public func getConversationCategory(conversationId: String) -> String? {
        db.select(column: Conversation.column(of: .category),
                  from: Conversation.self,
                  where: Conversation.column(of: .conversationId) == conversationId)
    }
    
    public func conversationList(limit: Int? = nil, circleId: String? = nil) -> [ConversationItem] {
        var sql: String
        if circleId == nil {
            sql = String(format: Self.sqlQueryConversation, "", "")
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
            return db.select(with: sql, arguments: [id])
        } else {
            return db.select(with: sql)
        }
    }
    
    public func createPlaceConversation(conversationId: String, ownerId: String) {
        guard !conversationId.isEmpty else {
            return
        }
        let conversationExists = db.recordExists(in: Conversation.self,
                                                 where: Conversation.column(of: .conversationId) == conversationId)
        guard !conversationExists else {
            return
        }
        let conversation = Conversation.createConversation(conversationId: conversationId, category: nil, recipientId: ownerId, status: ConversationStatus.START.rawValue)
        db.save(conversation)
    }
    
    public func createConversation(conversationId: String, name: String, members: [GroupUser], completion: @escaping (_ success: Bool) -> Void) {
        let createdAt = Date().toUTCString()
        let conversation = Conversation(conversationId: conversationId,
                                        ownerId: myUserId,
                                        category: ConversationCategory.GROUP.rawValue,
                                        name: name,
                                        iconUrl: nil,
                                        announcement: nil,
                                        lastMessageId: nil,
                                        lastMessageCreatedAt: createdAt,
                                        lastReadMessageId: nil,
                                        unseenMessageCount: 0,
                                        status: ConversationStatus.START.rawValue,
                                        draft: nil,
                                        muteUntil: nil,
                                        codeUrl: nil,
                                        pinTime: nil)
        var participants = members.map {
            Participant(conversationId: conversationId,
                        userId: $0.userId,
                        role: "",
                        status: ParticipantStatus.SUCCESS.rawValue,
                        createdAt: createdAt)
        }
        let me = Participant(conversationId: conversationId,
                             userId: myUserId,
                             role: ParticipantRole.OWNER.rawValue,
                             status: ParticipantStatus.SUCCESS.rawValue,
                             createdAt: createdAt)
        participants.append(me)
        
        do {
            try db.pool.write { (db) -> Void in
                try conversation.insert(db)
                try participants.save(db)
                db.afterNextTransactionCommit { (_) in
                    // Avoid potential deadlock
                    // TODO: Nested transactions could be auto detected, make some assertion?
                    DispatchQueue.global().async {
                        completion(true)
                    }
                }
            }
        } catch {
            Logger.write(error: error)
            completion(false)
        }
    }
    
    public func createNewConversation(response: ConversationResponse) -> (ConversationItem, [ParticipantUser]) {
        let conversationId = response.conversationId
        var conversation: ConversationItem!
        var participantUsers = [ParticipantUser]()
        
        db.write { (db) in
            try Conversation.createConversation(from: response, ownerId: myUserId, status: .SUCCESS).insert(db)
            let participants = response.participants.map {
                Participant(conversationId: conversationId, userId: $0.userId, role: $0.role, status: ParticipantStatus.SUCCESS.rawValue, createdAt: $0.createdAt)
            }
            try participants.insert(db)
            conversation = try ConversationItem.fetchOne(db, sql: ConversationDAO.sqlQueryConversationByCoversationId, arguments: [conversationId], adapter: nil)
            participantUsers = try ParticipantUser.fetchAll(db, sql: ParticipantDAO.sqlQueryGroupIconParticipants, arguments: [conversationId], adapter: nil)
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
        db.write { (db) in
            let request = try Conversation
                .select(Conversation.column(of: .status))
                .filter(Conversation.column(of: .conversationId) == conversationId)
            let oldStatus: Int? = try Row.fetchOne(db, request)?[0]
            
            guard oldStatus != targetStatus.rawValue else {
                return
            }
            
            if oldStatus == nil {
                let targetConversation = Conversation.createConversation(from: conversation,
                                                                         ownerId: ownerId,
                                                                         status: targetStatus)
                try targetConversation.insert(db)
            } else {
                let assignments = [
                    Conversation.column(of: .ownerId).set(to: ownerId),
                    Conversation.column(of: .category).set(to: conversation.category),
                    Conversation.column(of: .name).set(to: conversation.name),
                    Conversation.column(of: .announcement).set(to: conversation.announcement),
                    Conversation.column(of: .status).set(to: targetStatus.rawValue),
                    Conversation.column(of: .muteUntil).set(to: conversation.muteUntil),
                    Conversation.column(of: .codeUrl).set(to: conversation.codeUrl)
                ]
                try Conversation
                    .filter(Conversation.column(of: .conversationId) == conversationId)
                    .updateAll(db, assignments)
            }
            
            if conversation.participants.count > 0 {
                let participants = conversation.participants.map {
                    Participant(conversationId: conversationId, userId: $0.userId, role: $0.role, status: ParticipantStatus.START.rawValue, createdAt: $0.createdAt)
                }
                try participants.save(db)
                
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
                try sessionParticipants.save(db)
            }
            
            let userIds = try ParticipantDAO.shared.getNeedSyncParticipantIds(database: db, conversationId: conversationId)
            if userIds.count > 0 {
                ConcurrentJobQueue.shared.addJob(job: RefreshUserJob(userIds: userIds))
            }
            
            resultConversation = try ConversationItem.fetchOne(db, sql: ConversationDAO.sqlQueryConversationByCoversationId, arguments: [conversationId], adapter: nil)
            
            db.afterNextTransactionCommit { (_) in
                let change = ConversationChange(conversationId: conversationId,
                                                action: .updateConversation(conversation: conversation))
                NotificationCenter.default.post(onMainThread: conversationDidChangeNotification, object: change)
            }
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
        
        guard let oldConversation: Conversation = db.select(where: Conversation.column(of: .conversationId) == conversationId) else {
            return
        }
        
        if oldConversation.announcement != conversation.announcement, !conversation.announcement.isEmpty {
            AppGroupUserDefaults.User.hasUnreadAnnouncement[conversationId] = true
        }
        db.write { (db) in
            try Participant
                .filter(Participant.column(of: .conversationId) == conversationId)
                .deleteAll(db)
            let participants = conversation.participants.map {
                Participant(conversationId: conversationId, userId: $0.userId, role: $0.role, status: ParticipantStatus.START.rawValue, createdAt: $0.createdAt)
            }
            try participants.save(db)
            try ParticipantSessionDAO.shared.syncConversationParticipantSession(conversation: conversation, db: db)
            try db.execute(sql: ParticipantDAO.sqlUpdateStatus, arguments: [conversationId])
            
            let assignments = [
                Conversation.column(of: .ownerId).set(to: ownerId),
                Conversation.column(of: .category).set(to: conversation.category),
                Conversation.column(of: .name).set(to: conversation.name),
                Conversation.column(of: .announcement).set(to: conversation.announcement),
                Conversation.column(of: .status).set(to: ConversationStatus.SUCCESS.rawValue),
                Conversation.column(of: .muteUntil).set(to: conversation.muteUntil),
                Conversation.column(of: .codeUrl).set(to: conversation.codeUrl),
            ]
            try Conversation
                .filter(Conversation.column(of: .conversationId) == conversationId)
                .updateAll(db, assignments)
            
            let userIds = try ParticipantDAO.shared.getNeedSyncParticipantIds(database: db, conversationId: conversationId)
            if userIds.count > 0 {
                ConcurrentJobQueue.shared.addJob(job: RefreshUserJob(userIds: userIds))
            }
            
            db.afterNextTransactionCommit { (_) in
                if oldConversation.status != ConversationStatus.SUCCESS.rawValue {
                    let change = ConversationChange(conversationId: conversationId,
                                                    action: .updateConversationStatus(status: .SUCCESS))
                    NotificationCenter.default.post(onMainThread: conversationDidChangeNotification, object: change)
                }
                let change = ConversationChange(conversationId: conversationId,
                                                action: .updateConversation(conversation: conversation))
                NotificationCenter.default.post(onMainThread: conversationDidChangeNotification, object: change)
            }
        }
    }
    
    public func makeConversationId(userId: String, ownerUserId: String) -> String {
        return (min(userId, ownerUserId) + max(userId, ownerUserId)).toUUID()
    }
    
}

extension ConversationDAO {
    
    private func deleteFTSContent(with conversationId: String, from db: GRDB.Database) throws {
        let sql = "DELETE FROM \(Message.ftsTableName) WHERE conversation_id MATCH ?"
        try db.execute(sql: sql, arguments: [uuidTokenString(uuidString: conversationId)])
    }
    
    private func deleteTranscriptChildrenReferenced(by conversationId: String, from db: GRDB.Database) throws -> [String] {
        let transcriptMessageIds = try MessageDAO.shared.getTranscriptMessageIds(conversationId: conversationId, database: db)
        for id in transcriptMessageIds {
            try TranscriptMessage
                .filter(TranscriptMessage.column(of: .transcriptId) == id)
                .deleteAll(db)
        }
        return transcriptMessageIds
    }
    
}
