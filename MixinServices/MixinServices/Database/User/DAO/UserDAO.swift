import GRDB

public final class UserDAO: UserDatabaseDAO {
    
    public enum UserInfoKey {
        public static let user = "user"
        public static let app = "app"
    }
    
    public static let shared = UserDAO()
    
    public static let contactsDidChangeNotification = NSNotification.Name("one.mixin.services.UserDAO.contactsDidChange")
    public static let userDidChangeNotification = NSNotification.Name("one.mixin.services.UserDAO.userDidChange")
    public static let correspondingAppDidChange = NSNotification.Name("one.mixin.services.UserDAO.correspondingAppDidChange")
    
    private static let sqlQueryColumns = """
    SELECT u.user_id, u.full_name, u.biography, u.identity_number, u.avatar_url, u.phone, u.is_verified, u.mute_until, u.app_id, u.relationship, u.created_at, u.is_scam, '' AS role, a.creator_id as appCreatorId
    FROM users u
    LEFT JOIN apps a ON a.app_id = u.app_id
    """
    
    public func deleteUser(userId: String) {
        db.delete(User.self, where: User.column(of: .userId) == userId)
    }
    
    public func insertSystemUser(userId: String) {
        guard !isExist(userId: userId) else {
            return
        }
        let user = User.createSystemUser()
        db.save(user)
    }
    
    public func isExist(userId: String) -> Bool {
        db.recordExists(in: User.self, where: User.column(of: .userId) == userId)
    }
    
    public func getBlockUsers() -> [UserItem] {
        let sql = "\(Self.sqlQueryColumns) WHERE relationship = 'BLOCKING'"
        return db.select(with: sql)
    }
    
    public func getUser(userId: String) -> UserItem? {
        let sql = "\(Self.sqlQueryColumns) WHERE u.user_id = ?"
        return db.select(with: sql, arguments: [userId])
    }
    
    public func getUser(identityNumber: String) -> UserItem? {
        let sql = "\(Self.sqlQueryColumns) WHERE u.identity_number = ?"
        return db.select(with: sql, arguments: [identityNumber])
    }
    
    public func getUsers(keyword: String, limit: Int?) -> [UserItem] {
        var sql = """
        \(Self.sqlQueryColumns)
        WHERE u.relationship = 'FRIEND'
            AND u.identity_number > '0'
            AND ((u.full_name LIKE :escaped ESCAPE '/') OR (u.identity_number LIKE :escaped ESCAPE '/') OR (u.phone LIKE :escaped ESCAPE '/'))
        ORDER BY CASE WHEN LOWER(u.full_name) = :lowercased THEN 1 ELSE 0 END DESC
        """
        if let limit = limit {
            sql += " LIMIT \(limit)"
        }
        return db.select(with: sql, arguments: ["escaped": "%\(keyword.sqlEscaped)%", "lowercased": keyword.lowercased()])
    }
    
    public func getFriendUser(withAppId id: String) -> User? {
        let condition: SQLSpecificExpressible = User.column(of: .appId) == id
            && User.column(of: .relationship) == Relationship.FRIEND.rawValue
        return db.select(where: condition)
    }
    
    public func getUsers(with ids: [String]) -> [UserItem] {
        guard !ids.isEmpty else {
            return []
        }
        let wildcards = [String](repeating: "?", count: ids.count).joined(separator: ",")
        let sql = "\(UserDAO.sqlQueryColumns) WHERE u.user_id in (\(wildcards))"
        let users: [UserItem] = db.select(with: sql, arguments: StatementArguments(ids))
        let pairs = zip(users.map(\.userId), users)
        let map = [String: UserItem](uniqueKeysWithValues: pairs)
        return ids.compactMap { map[$0] }
    }
    
    public func getUsers(ofAppIds ids: [String]) -> [UserItem] {
        guard ids.count > 0 else {
            return []
        }
        let keys = ids.map { _ in "?" }.joined(separator: ",")
        let sql = "\(UserDAO.sqlQueryColumns) WHERE u.app_id in (\(keys))"
        let users: [UserItem] = db.select(with: sql, arguments: StatementArguments(ids))
        var userMap = [String: UserItem]()
        users.forEach { (user) in
            userMap[user.userId] = user
        }
        return ids.compactMap { userMap[$0] }
    }
    
    public func getAppUsers(inConversationOf conversationId: String) -> [User] {
        let sql = """
        SELECT u.user_id, u.full_name, u.biography, u.identity_number, u.avatar_url,
                u.phone, u.is_verified, u.mute_until, u.app_id, u.relationship, u.created_at, u.is_scam
        FROM participants p, apps a, users u
        WHERE p.conversation_id = ? AND p.user_id = u.user_id AND a.app_id = u.app_id
        """
        return db.select(with: sql, arguments: [conversationId])
    }
    
    public func getAppUsers() -> [User] {
        let sql = """
            SELECT u.user_id, u.full_name, u.biography, u.identity_number, u.avatar_url, u.phone, u.is_verified, u.mute_until, u.app_id, u.relationship, u.created_at, u.is_scam
            FROM apps a, users u
            WHERE a.app_id = u.app_id AND u.relationship = 'FRIEND'
            ORDER BY u.full_name ASC
        """
        return db.select(with: sql)
    }
    
    public func getFullname(userId: String) -> String? {
        db.select(column: User.column(of: .fullName),
                  from: User.self,
                  where: User.column(of: .userId) == userId)
    }
    
    public func appFriends(notIn ids: [String]) -> [User] {
        let condition = User.column(of: .relationship) == Relationship.FRIEND.rawValue
            && User.column(of: .appId) != nil
            && !ids.contains(User.column(of: .appId))
        return db.select(where: condition)
    }
    
    public func contacts() -> [UserItem] {
        let sql = "\(Self.sqlQueryColumns) WHERE u.relationship = 'FRIEND' AND u.identity_number > '0' ORDER BY u.created_at DESC"
        return db.select(with: sql)
    }
    
    public func contactsWithoutApp() -> [UserItem] {
        let sql = "\(Self.sqlQueryColumns) WHERE u.app_id IS NULL AND u.relationship = 'FRIEND' AND u.identity_number > '0' ORDER BY u.created_at DESC"
        return db.select(with: sql)
    }
    
    public func mentionRepresentation(identityNumbers: [String]) -> [String: String] {
        db.select(keyColumn: User.column(of: .identityNumber),
                  valueColumn: User.column(of: .fullName),
                  from: User.self,
                  where: identityNumbers.contains(User.column(of: .identityNumber)))
    }
    
    public func userIds(identityNumbers: [String]) -> [String] {
        db.select(column: User.column(of: .userId),
                  from: User.self,
                  where: identityNumbers.contains(User.column(of: .identityNumber)))
    }
    
    public func updateAccount(account: Account) {
        let user = User.createUser(from: account)
        db.save(user)
    }
    
    public func updateUsers(users: [UserResponse], sendNotificationAfterFinished: Bool = true, updateParticipantStatus: Bool = false, notifyContact: Bool = false) {
        guard users.count > 0 else {
            return
        }
        if Thread.isMainThread {
            DispatchQueue.global().async {
                UserDAO.shared.updateUsers(users: users, sendNotificationAfterFinished: sendNotificationAfterFinished, updateParticipantStatus: updateParticipantStatus, notifyContact: notifyContact)
            }
        } else {
            var isAppUpdated = false
            if sendNotificationAfterFinished, users.count == 1, let newApp = users[0].app {
                isAppUpdated = AppDAO.shared.getApp(appId: newApp.appId)?.updatedAt != newApp.updatedAt
            }
            db.write { (db) in
                for response in users {
                    let user = User.createUser(from: response)
                    try user.save(db)
                    if let app = user.app {
                        try app.save(db)
                    }
                    if updateParticipantStatus {
                        try Participant
                            .filter(Participant.column(of: .userId) == user.userId)
                            .updateAll(db, [Participant.column(of: .status).set(to: ParticipantStatus.SUCCESS.rawValue)])
                    }
                }
                db.afterNextTransactionCommit { (_) in
                    if sendNotificationAfterFinished {
                        if users.count == 1 {
                            let user = UserItem.createUser(from: users[0])
                            NotificationCenter.default.post(onMainThread: Self.userDidChangeNotification,
                                                            object: self,
                                                            userInfo: [Self.UserInfoKey.user: user])
                        }
                    }
                    if isAppUpdated {
                        NotificationCenter.default.post(onMainThread: Self.correspondingAppDidChange,
                                                        object: self,
                                                        userInfo: [Self.UserInfoKey.app: users[0].app])
                    }
                    if notifyContact {
                        NotificationCenter.default.post(onMainThread: Self.contactsDidChangeNotification,
                                                        object: self)
                    }
                }
            }
        }
        
    }
    
    public func updateUser(with userId: String, muteUntil: String) {
        db.update(User.self,
                  assignments: [User.column(of: .muteUntil).set(to: muteUntil)],
                  where: User.column(of: .userId) == userId) { _ in
            DispatchQueue.global().async {
                guard let user = self.getUser(userId: userId) else {
                    return
                }
                NotificationCenter.default.post(onMainThread: Self.userDidChangeNotification,
                                                object: self,
                                                userInfo: [Self.UserInfoKey.user: user])
            }
        }
    }
    
    public func saveUser(user response: UserResponse) -> UserItem? {
        var userItem: UserItem?
        db.write { (db) in
            let user = User.createUser(from: response)
            try user.save(db)
            if let app = user.app {
                try app.save(db)
            }
            db.afterNextTransactionCommit { (_) in
                userItem = self.getUser(userId: user.userId)
            }
        }
        return userItem
    }
    
}
