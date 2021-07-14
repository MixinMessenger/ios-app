import Foundation
import GRDB

public final class ParticipantDAO: UserDatabaseDAO {
    
    public enum UserInfoKey {
        public static let conversationId = "cid"
    }
    
    public static let shared = ParticipantDAO()
    
    public static let participantDidChangeNotification = NSNotification.Name("one.mixin.services.ParticipantDAO.participantDidChange")
    
    private static let sqlQueryColumns = """
    SELECT p.conversation_id, p.user_id, p.role, p.status, p.created_at FROM participants p
    """
    static let sqlQueryGroupIconParticipants = """
    SELECT u.user_id as userId, u.identity_number as userIdentityNumber, u.full_name as userFullName, u.avatar_url as userAvatarUrl, p.role, p.conversation_id as conversationId
    FROM participants p
    INNER JOIN users u ON u.user_id = p.user_id
    WHERE p.conversation_id = ? AND ifnull(u.full_name, '') <> ''
    ORDER BY p.created_at ASC
    LIMIT 4
    """
    static let sqlUpdateStatus = "UPDATE participants SET status = 1 WHERE conversation_id = ? AND user_id in (SELECT user_id FROM users)"
    
    public func isAdmin(conversationId: String, userId: String) -> Bool {
        let condition: SQLSpecificExpressible = Participant.column(of: .conversationId) == conversationId
            && Participant.column(of: .userId) == userId
            && [ParticipantRole.ADMIN.rawValue, ParticipantRole.OWNER.rawValue].contains(Participant.column(of: .role))
        return db.recordExists(in: Participant.self, where: condition)
    }
    
    public func getParticipantId(conversationId: String, identityNumber: String) -> String? {
        let sql = """
        SELECT u.user_id FROM users u
        INNER JOIN participants p ON p.user_id = u.user_id
        WHERE p.conversation_id = ? AND u.identity_number = ?
        """
        return db.select(with: sql, arguments: [conversationId, identityNumber])
    }
    
    public func getGroupIconParticipants(conversationId: String) -> [ParticipantUser] {
        return db.select(with: Self.sqlQueryGroupIconParticipants, arguments: [conversationId])
    }
    
    public func getParticipants(conversationId: String) -> [UserItem] {
        let sql = """
        SELECT u.user_id, u.full_name, u.biography, u.identity_number, u.avatar_url, u.phone, u.is_verified, u.mute_until, u.app_id, u.relationship, u.created_at, u.is_scam, a.creator_id as appCreatorId, p.role
        FROM participants p
        INNER JOIN users u ON u.user_id = p.user_id
        LEFT JOIN apps a ON a.app_id = u.app_id
        WHERE p.conversation_id = ?
        ORDER BY p.created_at DESC
        """
        return db.select(with: sql, arguments: [conversationId])
    }
    
    public func getParticipent(conversationId: String, userId: String) -> Participant? {
        let condition: SQLSpecificExpressible = Participant.column(of: .conversationId) == conversationId
            && Participant.column(of: .userId) == userId
        return db.select(where: condition)
    }
    
    public func getAllParticipants() -> [Participant] {
        db.selectAll()
    }
    
    public func getParticipantCount(conversationId: String) -> Int {
        db.count(in: Participant.self,
                 where: Participant.column(of: .conversationId) == conversationId)
    }
    
    public func userId(_ userId: String, isParticipantOfConversationId conversationId: String) -> Bool {
        let condition = Participant.column(of: .conversationId) == conversationId
            && Participant.column(of: .userId) == userId
        return db.recordExists(in: Participant.self, where: condition)
    }
    
    public func updateParticipantStatus(userId: String, status: ParticipantStatus) {
        db.update(Participant.self,
                  assignments: [Participant.column(of: .status).set(to: status.rawValue)],
                  where: Participant.column(of: .userId) == userId)
    }
    
    public func getNeedSyncParticipantIds(database: GRDB.Database, conversationId: String) throws -> [String] {
        let sql = """
        SELECT p.user_id FROM participants p
        LEFT JOIN users u ON u.user_id = p.user_id
        WHERE p.conversation_id = ? AND u.identity_number IS NULL AND p.user_id != ?
        """
        return try String.fetchAll(database, sql: sql, arguments: [conversationId, myUserId], adapter: nil)
    }
    
    public func getSyncParticipantIds() -> [String] {
        let ids: [String] = db.select(column: Participant.column(of: .userId),
                                      from: Participant.self,
                                      where: Participant.column(of: .status) == ParticipantStatus.START.rawValue)
        return Array(Set(ids))
    }
    
    public func updateParticipantRole(message: Message, conversationId: String, participantId: String, role: String, source: String, silentNotification: Bool) -> Bool {
        db.write { (db) in
            let condition: SQLSpecificExpressible = Participant.column(of: .conversationId) == conversationId
                && Participant.column(of: .userId) == participantId
            let assignment = Participant.column(of: .role).set(to: role)
            try Participant.filter(condition).updateAll(db, [assignment])
            if !role.isEmpty {
                try MessageDAO.shared.insertMessage(database: db, message: message, messageSource: source, silentNotification: silentNotification)
            }
            db.afterNextTransactionCommit { _ in
                NotificationCenter.default.post(onMainThread: Self.participantDidChangeNotification,
                                                object: self,
                                                userInfo: [Self.UserInfoKey.conversationId: conversationId])
            }
        }
    }
    
    public func addParticipant(message : Message, conversationId: String, participantId: String, updatedAt: String, status: ParticipantStatus, source: String, silentNotification: Bool) -> Bool {
        let participant = Participant(conversationId: conversationId,
                                      userId: participantId,
                                      role: "",
                                      status: status.rawValue,
                                      createdAt: updatedAt)
        return db.write { (db) in
            try participant.save(db)
            try MessageDAO.shared.insertMessage(database: db, message: message, messageSource: source, silentNotification: silentNotification)
            db.afterNextTransactionCommit { _ in
                NotificationCenter.default.post(onMainThread: Self.participantDidChangeNotification,
                                                object: self,
                                                userInfo: [Self.UserInfoKey.conversationId: conversationId])
            }
        }
    }
    
    public func removeParticipant(message: Message, conversationId: String, userId: String, source: String, silentNotification: Bool) -> Bool {
        db.write { (db) in
            try Participant
                .filter(Participant.column(of: .conversationId) == conversationId && Participant.column(of: .userId) == userId)
                .deleteAll(db)
            try ParticipantSession
                .filter(ParticipantSession.column(of: .conversationId) == conversationId && ParticipantSession.column(of: .userId) == userId)
                .deleteAll(db)
            try ParticipantSession
                .filter(ParticipantSession.column(of: .conversationId) == conversationId)
                .updateAll(db, ParticipantSession.column(of: .sentToServer).set(to: nil))
            try MessageDAO.shared.insertMessage(database: db, message: message, messageSource: source, silentNotification: silentNotification)
            NotificationCenter.default.post(name: ReceiveMessageService.senderKeyDidChangeNotification,
                                            object: self,
                                            userInfo: [ReceiveMessageService.UserInfoKey.conversationId: conversationId])
            db.afterNextTransactionCommit { (_) in
                NotificationCenter.default.post(onMainThread: Self.participantDidChangeNotification,
                                                object: self,
                                                userInfo: [Self.UserInfoKey.conversationId: conversationId])
            }
        }
    }
    
    public func participants(conversationId: String, limit: Int? = nil) -> [Participant] {
        var sql = """
        \(Self.sqlQueryColumns)
        LEFT JOIN users u ON p.user_id = u.user_id
        WHERE p.conversation_id = ? AND u.identity_number > '0'
        """
        if let limit = limit {
            sql += " LIMIT \(limit)"
        }
        return db.select(with: sql, arguments: [conversationId])
    }
    
    public func participantRequests(conversationId: String, currentAccountId: String) -> [ParticipantRequest] {
        let participants = self.participants(conversationId: conversationId, limit: 50)
        return participants
            .filter({ $0.userId != currentAccountId })
            .map({ ParticipantRequest(userId: $0.userId, role: $0.role) })
    }
    
}
