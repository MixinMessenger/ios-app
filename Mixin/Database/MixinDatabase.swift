import WCDBSwift

class MixinDatabase: BaseDatabase {

    private static let databaseVersion: Int = 7

    static let shared = MixinDatabase()

    private lazy var _database = Database(withPath: MixinFile.databaseURL.path)
    override var database: Database! {
        get { return _database }
        set { }
    }

    override func configure(reset: Bool = false) {
        if MixinFile.databaseURL.path != _database.path {
            _database.close()
            _database = Database(withPath: MixinFile.databaseURL.path)
        }
        do {
            try database.run(transaction: {
                let currentVersion = DatabaseUserDefault.shared.mixinDatabaseVersion
                try self.createBefore(database: database, currentVersion: currentVersion)

                try database.create(of: Asset.self)
                try database.create(table: Asset.topAssetsTableName, of: Asset.self)
                try database.create(of: Snapshot.self)
                try database.create(of: Sticker.self)
                try database.create(of: StickerRelationship.self)
                try database.create(of: Album.self)
                try database.create(of: MessageBlaze.self)
                try database.create(of: MessageHistory.self)
                try database.create(of: SentSenderKey.self)
                try database.create(of: App.self)

                try database.create(of: User.self)
                try database.create(of: Conversation.self)
                try database.create(of: Message.self)
                try database.create(of: Participant.self)
                
                try database.create(of: Address.self)
                try database.create(of: Job.self)
                try database.create(of: ResendMessage.self)

                try self.createAfter(database: database, currentVersion: currentVersion)

                try database.prepareUpdateSQL(sql: MessageDAO.sqlTriggerLastMessageDelete).execute()

                DatabaseUserDefault.shared.mixinDatabaseVersion = MixinDatabase.databaseVersion
            })
        } catch {
            #if DEBUG
                print("======MixinDatabase...configure...error:\(error)")
            #endif
            UIApplication.traceError(error)
        }
    }

    private func createBefore(database: Database, currentVersion: Int) throws {
        guard currentVersion > 0 else {
            return
        }

        if currentVersion < 4 {
            try database.prepareUpdateSQL(sql: "DROP INDEX IF EXISTS messages_index1").execute()
            try database.prepareUpdateSQL(sql: "DROP INDEX IF EXISTS messages_index2").execute()
        }

        if currentVersion < 5 {
            try database.drop(table: Sticker.tableName)
            try database.drop(table: "sticker_albums")
        }

        if currentVersion < 6 {
            try database.prepareUpdateSQL(sql: "DROP INDEX IF EXISTS messages_status_index").execute()
            try database.prepareUpdateSQL(sql: "DROP TRIGGER IF EXISTS conversation_unseen_message_count_update").execute()
        }

        if currentVersion < 7 {
            try database.prepareUpdateSQL(sql: "DROP TRIGGER IF EXISTS conversation_unseen_message_count_insert").execute()
            try database.prepareUpdateSQL(sql: "DROP TRIGGER IF EXISTS conversation_last_message_update").execute()
        }
    }

    private func createAfter(database: Database, currentVersion: Int) throws {
        guard currentVersion > 0 else {
            return
        }

        if currentVersion < 4, try database.isColumnExist(tableName: Snapshot.tableName, columnName: "counter_user_id") {
            try database.prepareUpdateSQL(sql: "UPDATE snapshots SET opponent_id = counter_user_id").execute()
        }
    }

    func logout() {
        deleteAll(table: SentSenderKey.tableName)
        database.close()
    }
    
}

extension MixinDatabase {
    
    class NullValue: ColumnEncodable {
        
        static var columnType: ColumnType {
            return .null
        }
        
        func archivedValue() -> FundamentalValue {
            return FundamentalValue(nil)
        }
        
    }

}
