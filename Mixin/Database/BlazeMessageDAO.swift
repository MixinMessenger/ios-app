import WCDBSwift

final class BlazeMessageDAO {

    static let shared = BlazeMessageDAO()

    private let jsonDecoder = JSONDecoder()

    func isExist(data: BlazeMessageData) -> Bool {
        return MixinDatabase.shared.isExist(type: MessageBlaze.self, condition: MessageBlaze.Properties.messageId == data.messageId)
    }

    func insertOrReplace(data: BlazeMessageData, originalData: String?) -> Bool {
        guard let messageData = originalData?.data(using: .utf8) else {
            return false
        }
        return MixinDatabase.shared.insertOrReplace(objects: [MessageBlaze(messageId: data.messageId, conversationId: data.conversationId, isSessionMessage: data.isSessionMessage, message: messageData, createdAt: data.createdAt)])
    }

    func getCount() -> Int {
        return MixinDatabase.shared.getCount(on: MessageBlaze.Properties.messageId.count(), fromTable: MessageBlaze.tableName)
    }

    func getBlazeMessageData(limit: Int) -> [BlazeMessageData] {
        return MixinDatabase.shared.getCodables(on: [MessageBlaze.Properties.message], fromTable: MessageBlaze.tableName, orderBy: [MessageBlaze.Properties.createdAt.asOrder(by: .ascending)], limit: limit) { (rows) -> [BlazeMessageData] in
            var result = [BlazeMessageData]()
            for row in rows {
                guard let data = (try? jsonDecoder.decode(BlazeMessageData.self, from: row[0].dataValue)) else {
                    continue
                }
                result.append(data)
            }
            return result
        }
    }

    func getBlazeMessageData(conversationId: String, limit: Int) -> [BlazeMessageData] {
        return MixinDatabase.shared.getCodables(on: [MessageBlaze.Properties.message], fromTable: MessageBlaze.tableName, condition: MessageBlaze.Properties.conversationId == conversationId && MessageBlaze.Properties.isSessionMessage == false, orderBy: [MessageBlaze.Properties.createdAt.asOrder(by: .ascending)], limit: limit) { (rows) -> [BlazeMessageData] in
            var result = [BlazeMessageData]()
            let decoder = JSONDecoder()
            for row in rows {
                guard let data = (try? decoder.decode(BlazeMessageData.self, from: row[0].dataValue)) else {
                    continue
                }
                result.append(data)
            }
            return result
        }
    }

    func delete(data: BlazeMessageData) {
        MixinDatabase.shared.delete(table: MessageBlaze.tableName, condition: MessageBlaze.Properties.messageId == data.messageId)
    }
}

