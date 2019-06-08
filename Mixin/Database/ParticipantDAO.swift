import Foundation
import WCDBSwift

final class ParticipantDAO {

    static let shared = ParticipantDAO()

    private static let sqlQueryColumns = """
    SELECT p.conversation_id, p.user_id, p.role, p.status, p.created_at FROM participants p
    """
    static let sqlQueryNotSentKeyParticipants = """
    \(sqlQueryColumns)
    LEFT JOIN users u ON p.user_id = u.user_id
    WHERE p.conversation_id = ?
    AND p.user_id NOT IN (SELECT user_id FROM sent_sender_keys WHERE conversation_id = ?)
    AND p.user_id != ? AND ifnull(u.app_id, '') = ''
    """
    static let sqlQueryNotAppParticipants = """
    \(sqlQueryColumns)
    LEFT JOIN users u ON p.user_id = u.user_id
    WHERE p.conversation_id = ? AND p.user_id != ? AND ifnull(u.app_id, '') = ''
    """
    static let sqlQueryParticipants = """
    \(sqlQueryColumns)
    LEFT JOIN users u ON p.user_id = u.user_id
    WHERE p.conversation_id = ? AND u.identity_number > '0'
    """
    static let sqlUpdateStatus = "UPDATE participants SET status = 1 WHERE conversation_id = ? AND user_id in (SELECT user_id FROM users)"
    private static let sqlQueryParticipantUsers = """
    SELECT u.user_id, u.full_name, u.identity_number, u.avatar_url, u.phone, u.is_verified, u.mute_until, u.app_id, u.relationship, u.created_at, a.description as appDescription, a.creator_id as appCreatorId, p.role
    FROM participants p
    INNER JOIN users u ON u.user_id = p.user_id
    LEFT JOIN apps a ON a.app_id = u.app_id
    WHERE p.conversation_id = ?
    ORDER BY p.created_at DESC
    """
    private static let sqlQueryGroupIconParticipants = """
    SELECT u.user_id as userId, u.identity_number as userIdentityNumber, u.full_name as userFullName, u.avatar_url as userAvatarUrl, p.role, p.conversation_id as conversationId
    FROM participants p
    INNER JOIN users u ON u.user_id = p.user_id
    WHERE p.conversation_id = ? AND ifnull(u.full_name, '') <> ''
    ORDER BY p.created_at ASC
    LIMIT 4
    """

    func isAdmin(conversationId: String, userId: String) -> Bool {
        return MixinDatabase.shared.isExist(type: Participant.self, condition: Participant.Properties.conversationId == conversationId && Participant.Properties.userId == userId && (Participant.Properties.role == ParticipantRole.ADMIN.rawValue || Participant.Properties.role == ParticipantRole.OWNER.rawValue))
    }

    func getGroupIconParticipants(conversationId: String) -> [ParticipantUser] {
        return MixinDatabase.shared.getCodables(sql: ParticipantDAO.sqlQueryGroupIconParticipants, values: [conversationId], inTransaction: false)
    }

    func getParticipants(conversationId: String) -> [UserItem] {
        return MixinDatabase.shared.getCodables(sql: ParticipantDAO.sqlQueryParticipantUsers, values: [conversationId])
    }
    
    func getParticipantCount(conversationId: String) -> Int {
        return MixinDatabase.shared.getCount(on: Participant.Properties.userId.count(),
                                             fromTable: Participant.tableName,
                                             condition: Participant.Properties.conversationId == conversationId)
    }
    
    func userId(_ userId: String, isParticipantOfConversationId conversationId: String) -> Bool {
        let condition = Participant.Properties.conversationId == conversationId
            && Participant.Properties.userId == userId
        return MixinDatabase.shared.isExist(type: Participant.self, condition: condition, inTransaction: false)
    }
    
    func updateParticipantStatus(userId: String, status: ParticipantStatus) {
        MixinDatabase.shared.update(maps: [(Participant.Properties.status, status.rawValue)], tableName: Participant.tableName, condition: Participant.Properties.userId == userId)
    }

    func getNeedSyncParticipantIds(database: Database, conversationId: String) throws -> [String] {
        let pUserIdColumn = Participant.Properties.userId.in(table: Participant.tableName)
        let pConversationIdColumn = Participant.Properties.conversationId.in(table: Participant.tableName)
        let userIdColumn = User.Properties.userId.in(table: User.tableName)
        let identityNumberColumn = User.Properties.identityNumber.in(table: User.tableName)

        let joinClause = JoinClause(with: Participant.tableName)
            .join(User.tableName, with: .left)
            .on(userIdColumn == pUserIdColumn)
        let statementSelect = StatementSelect().select(pUserIdColumn).from(joinClause).where(pConversationIdColumn == conversationId && identityNumberColumn.isNull() && pUserIdColumn != AccountAPI.shared.accountUserId)
        let coreStatement = try database.prepare(statementSelect)

        var result = [String]()
        while try coreStatement.step() {
            result.append(coreStatement.value(atIndex: 0).stringValue)
        }
        return result
    }

    func getSyncParticipantIds() -> [String] {
        return MixinDatabase.shared.getStringValues(column: Participant.Properties.userId.asColumnResult(), tableName: Participant.tableName, condition: Participant.Properties.status == ParticipantStatus.START.rawValue, inTransaction: false).distinct()
    }

    func getNotSentKeyParticipants(conversationId: String, accountId: String) -> [Participant] {
        return MixinDatabase.shared.getCodables(sql: ParticipantDAO.sqlQueryNotSentKeyParticipants, values: [conversationId, conversationId, accountId])
    }

    func getNotAppParticipants(conversationId: String, accountId: String) -> [Participant] {
        return MixinDatabase.shared.getCodables(sql: ParticipantDAO.sqlQueryNotAppParticipants, values: [conversationId, accountId])
    }

    func updateParticipantRole(message: Message, conversationId: String, participantId: String, role: String, source: String) -> Bool {
        return MixinDatabase.shared.transaction { (db) in
            try db.update(table: Participant.tableName, on: [Participant.Properties.role], with: [role], where: Participant.Properties.conversationId == conversationId && Participant.Properties.userId == participantId)
            try MessageDAO.shared.insertMessage(database: db, message: message, messageSource: source)
            NotificationCenter.default.afterPostOnMain(name: .ParticipantDidChange, object: conversationId)
        }
    }

    func addParticipant(message : Message, conversationId: String, participantId: String, updatedAt: String, status: ParticipantStatus, source: String) -> Bool {
        return MixinDatabase.shared.transaction { (db) in
            let participant = Participant(conversationId: conversationId, userId: participantId, role: "", status: status.rawValue, createdAt: updatedAt)
            try db.insertOrReplace(objects: [participant], intoTable: Participant.tableName)
            try MessageDAO.shared.insertMessage(database: db, message: message, messageSource: source)
            NotificationCenter.default.afterPostOnMain(name: .ParticipantDidChange, object: conversationId)
        }
    }

    func removeParticipant(message: Message, conversationId: String, userId: String, source: String) -> Bool {
        return MixinDatabase.shared.transaction { (db) in
            try db.delete(fromTable: Participant.tableName, where: Participant.Properties.conversationId == conversationId && Participant.Properties.userId == userId)
            try MessageDAO.shared.insertMessage(database: db, message: message, messageSource: source)
            NotificationCenter.default.afterPostOnMain(name: .ParticipantDidChange, object: conversationId)
        }
    }

    func removeParticipant(conversationId: String) {
        let userId = AccountAPI.shared.accountUserId
        MixinDatabase.shared.transaction { (db) in
            try db.delete(fromTable: Participant.tableName, where: Participant.Properties.conversationId == conversationId && Participant.Properties.userId == userId)
            try db.update(table: Conversation.tableName, on: [Conversation.Properties.status], with: [ConversationStatus.QUIT.rawValue], where: Conversation.Properties.conversationId == conversationId)
            NotificationCenter.default.afterPostOnMain(name: .ParticipantDidChange, object: conversationId)
        }
    }

    func participants(conversationId: String) -> [Participant] {
        return MixinDatabase.shared.getCodables(sql: ParticipantDAO.sqlQueryParticipants, values: [conversationId])
    }

    func participantRequests(conversationId: String, currentAccountId: String) -> [ParticipantRequest] {
        let participants = ParticipantDAO.shared.participants(conversationId: conversationId)
        return participants
            .filter({ $0.userId != currentAccountId })
            .map({ ParticipantRequest(userId: $0.userId, role: $0.role) })
    }

}
