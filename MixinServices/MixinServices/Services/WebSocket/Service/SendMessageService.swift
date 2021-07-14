import Foundation
import GRDB

public class SendMessageService: MixinService {
    
    public static let shared = SendMessageService()
    
    internal static let recallableSuffices = [
        "_TEXT", "_STICKER", "_CONTACT", "_IMAGE", "_DATA",
        "_AUDIO", "_VIDEO", "_LIVE", "_POST", "_LOCATION",
        "_TRANSCRIPT"
    ]
    
    public let jobCreationQueue = DispatchQueue(label: "one.mixin.services.queue.send.message.job.creation")
    
    @Synchronized(value: false)
    public private(set) var isRequestingKrakenPeers: Bool
    
    private let dispatchQueue = DispatchQueue(label: "one.mixin.services.queue.send.messages")
    private let httpDispatchQueue = DispatchQueue(label: "one.mixin.services.queue.send.http.messages")
    private var httpProcessing = false
    
    public func recallMessage(item: MessageItem) {
        let category = item.category
        let conversationId = item.conversationId
        let messageId = item.messageId
        guard category == MessageCategory.APP_CARD.rawValue || SendMessageService.recallableSuffices.contains(where: category.hasSuffix) else {
            return
        }
        
        let blazeMessage = BlazeMessage(recallMessageId: messageId, conversationId: conversationId)
        let job = Job(jobId: UUID().uuidString.lowercased(), action: JobAction.SEND_MESSAGE, conversationId: conversationId, blazeMessage: blazeMessage)
        
        ReceiveMessageService.shared.stopRecallMessage(item: item)
        
        let database: Database = UserDatabase.current
        let quoteCondition: SQLSpecificExpressible = Message.column(of: .conversationId) == conversationId
            && Message.column(of: .quoteMessageId) == messageId
        let quoteMessageIds: [String] = database.select(column: Message.column(of: .messageId),
                                                        from: Message.self,
                                                        where: quoteCondition)
        database.write { (db) in
            try job.save(db)
            try MessageDAO.shared.recallMessage(database: db,
                                                messageId: messageId,
                                                conversationId: conversationId,
                                                category: category,
                                                status: item.status,
                                                quoteMessageIds: quoteMessageIds)
        }
        SendMessageService.shared.processMessages()
    }
    
    public func sendMessage(message: Message, data: String?, immediatelySend: Bool = true, silentNotification: Bool = false) {
        let needsEncodeCategories: [MessageCategory] = [
            .PLAIN_TEXT, .PLAIN_POST, .PLAIN_LOCATION, .PLAIN_TRANSCRIPT
        ]
        let shouldEncodeContent = needsEncodeCategories.map(\.rawValue).contains(message.category)
        let content = shouldEncodeContent ? data?.base64Encoded() : data
        let job = Job(message: message, data: content, silentNotification: silentNotification)
        UserDatabase.current.save(job)
        if immediatelySend {
            SendMessageService.shared.processMessages()
        }
    }
    
    @discardableResult
    public func saveUploadJob(message: Message) -> String {
        let job: Job
        if message.category.hasSuffix("_TRANSCRIPT") {
            job = Job(attachmentMessage: message.messageId, action: .UPLOAD_TRANSCRIPT_ATTACHMENT)
        } else {
            job = Job(attachmentMessage: message.messageId, action: .UPLOAD_ATTACHMENT)
        }
        UserDatabase.current.save(job)
        return job.jobId
    }
    
    public func recoverAttachmentMessages(messageIds: [String]) {
        let jobs = messageIds.map { Job(attachmentMessage: $0, action: .RECOVER_ATTACHMENT) }
        UserDatabase.current.save(jobs)
    }
    
    public func sendWebRTCMessage(message: Message, recipientId: String) {
        let job = Job(webRTCMessage: message, recipientId: recipientId)
        UserDatabase.current.save(job)
        SendMessageService.shared.processMessages()
    }
    
    func sendMessage(conversationId: String, userId: String, sessionId: String?, action: JobAction) {
        let job = Job(jobId: UUID().uuidString.lowercased(), action: action, userId: userId, conversationId: conversationId, sessionId: sessionId)
        UserDatabase.current.save(job)
        SendMessageService.shared.processMessages()
    }
    
    func sendMessage(conversationId: String, userId: String, blazeMessage: BlazeMessage, action: JobAction) {
        let job = Job(jobId: blazeMessage.id, action: action, userId: userId, conversationId: conversationId, blazeMessage: blazeMessage)
        UserDatabase.current.save(job)
        SendMessageService.shared.processMessages()
    }
    
    public func resendMessages(conversationId: String, userId: String, sessionId: String, messageIds: [String]) {
        guard let participent = ParticipantDAO.shared.getParticipent(conversationId: conversationId, userId: userId) else {
            return
        }
        
        var jobs = [Job]()
        var resendMessages = [ResendSessionMessage]()
        for messageId in messageIds {
            guard !ResendSessionMessageDAO.shared.isExist(messageId: messageId, userId: userId, sessionId: sessionId) else {
                continue
            }
            guard let needResendMessage = MessageDAO.shared.getMessage(messageId: messageId, userId: currentAccountId), needResendMessage.category != MessageCategory.MESSAGE_RECALL.rawValue else {
                resendMessages.append(ResendSessionMessage(messageId: messageId, userId: userId, sessionId: sessionId, status: 0))
                continue
            }
            guard needResendMessage.createdAt > participent.createdAt else {
                continue
            }
            
            let param = BlazeMessageParam(conversationId: conversationId, recipientId: userId, status: MessageStatus.SENT.rawValue, messageId: messageId, sessionId: sessionId)
            let blazeMessage = BlazeMessage(params: param, action: BlazeMessageAction.createMessage.rawValue)
            jobs.append(Job(jobId: blazeMessage.id, action: .RESEND_MESSAGE, userId: userId, conversationId: conversationId, resendMessageId: UUID().uuidString.lowercased(), sessionId: sessionId, blazeMessage: blazeMessage))
            resendMessages.append(ResendSessionMessage(messageId: messageId, userId: userId, sessionId: sessionId, status: 1))
        }
        
        UserDatabase.current.write { (db) in
            try jobs.save(db)
            try resendMessages.save(db)
        }
        SendMessageService.shared.processMessages()
    }
    
    public func sendReadMessages(conversationId: String) {
        DispatchQueue.global().async {
            let condition: SQLSpecificExpressible = Message.column(of: .conversationId) == conversationId
                && Message.column(of: .status) == MessageStatus.DELIVERED.rawValue
                && Message.column(of: .userId) != myUserId
            let messageIds: [String] = UserDatabase.current.select(column: Message.column(of: .messageId),
                                                                   from: Message.self,
                                                                   where: condition,
                                                                   order: [Message.column(of: .createdAt).asc])
            var position = 0
            let pageCount = AppGroupUserDefaults.Account.isDesktopLoggedIn ? 1000 : 2000
            while messageIds.count > 0 && position < messageIds.count {
                let nextPosition = position + pageCount > messageIds.count ? messageIds.count : position + pageCount
                let ids = Array(messageIds[position..<nextPosition])
                var jobs = [Job]()
                
                guard let lastMessageId = ids.last else {
                    return
                }
                let lastRowID: Int = UserDatabase.current.select(column: .rowID, from: Message.self, where: Message.column(of: .messageId) == lastMessageId)!
                if ids.count == 1 {
                    let messageId = ids[0]
                    let blazeMessage = BlazeMessage(ackBlazeMessage: messageId, status: MessageStatus.READ.rawValue)
                    jobs.append(Job(jobId: blazeMessage.id, action: .SEND_ACK_MESSAGE, blazeMessage: blazeMessage))
                    
                    if AppGroupUserDefaults.Account.isDesktopLoggedIn {
                        jobs.append(Job(sessionRead: conversationId, messageId: messageId))
                    }
                } else {
                    for i in stride(from: 0, to: ids.count, by: 100) {
                        let by = i + 100 > ids.count ? ids.count : i + 100
                        let messages: [TransferMessage] = ids[i..<by].map { TransferMessage(messageId: $0, status: MessageStatus.READ.rawValue) }
                        let blazeMessage = BlazeMessage(params: BlazeMessageParam(messages: messages), action: BlazeMessageAction.acknowledgeMessageReceipts.rawValue)
                        jobs.append(Job(jobId: blazeMessage.id, action: .SEND_ACK_MESSAGES, blazeMessage: blazeMessage))
                        
                        if let sessionId = AppGroupUserDefaults.Account.extensionSession {
                            let blazeMessage = BlazeMessage(params: BlazeMessageParam(sessionId: sessionId, conversationId: conversationId, ackMessages: messages), action: BlazeMessageAction.createMessage.rawValue)
                            jobs.append(Job(jobId: blazeMessage.id, action: .SEND_SESSION_MESSAGES, blazeMessage: blazeMessage))
                        }
                    }
                }
                
                let isLastLoop = nextPosition >= messageIds.count
                UserDatabase.current.write { (db) in
                    try jobs.insert(db)
                    try db.execute(sql: "UPDATE messages SET status = '\(MessageStatus.READ.rawValue)' WHERE conversation_id = ? AND status = ? AND user_id != ? AND ROWID <= ?",
                                   arguments: [conversationId, MessageStatus.DELIVERED.rawValue, myUserId, lastRowID])
                    try MessageDAO.shared.updateUnseenMessageCount(database: db, conversationId: conversationId)
                    if isLastLoop {
                        db.afterNextTransactionCommit { (_) in
                            NotificationCenter.default.post(name: MixinService.messageReadStatusDidChangeNotification, object: self)
                            NotificationCenter.default.post(onMainThread: conversationDidChangeNotification, object: nil)
                        }
                    }
                }
                
                position = nextPosition
                if !isLastLoop {
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
            SendMessageService.shared.processMessages()
        }
    }
    
    public func sendMentionMessageRead(conversationId: String, messageId: String) {
        UserDatabase.current.write { (db) in
            let condition: SQLSpecificExpressible = MessageMention.column(of: .messageId) == messageId
                && !MessageMention.column(of: .hasRead)
            let changes = try MessageMention.filter(condition).updateAll(db, [MessageMention.column(of: .hasRead).set(to: true)])
            
            guard changes > 0 else {
                return
            }
            
            db.afterNextTransactionCommit { (_) in
                NotificationCenter.default.post(onMainThread: conversationDidChangeNotification, object: nil)
            }

            if AppGroupUserDefaults.Account.isDesktopLoggedIn {
                let job = Job(sessionRead: conversationId, messageId: messageId, status: MessageMentionStatus.MENTION_READ.rawValue)
                try job.save(db)
            }
        }
    }
    
    public func sendAckMessage(messageId: String, status: MessageStatus) {
        let blazeMessage = BlazeMessage(ackBlazeMessage: messageId, status: status.rawValue)
        let action: JobAction = status == .DELIVERED ? .SEND_DELIVERED_ACK_MESSAGE : .SEND_ACK_MESSAGE
        let job = Job(jobId: blazeMessage.id, action: action, blazeMessage: blazeMessage)
        UserDatabase.current.save(job)
        SendMessageService.shared.processMessages()
    }
    
    public func processMessages() {
        processHttpMessages()
        if !isAppExtension {
            processWebSocketMessages()
        }
    }
    
    public func processHttpMessages() {
        guard !httpProcessing else {
            return
        }
        httpProcessing = true
        
        httpDispatchQueue.async {
            defer {
                SendMessageService.shared.httpProcessing = false
            }
            repeat {
                guard LoginManager.shared.isLoggedIn else {
                    return
                }
                guard !MixinService.isStopProcessMessages else {
                    return
                }
                
                let jobs = JobDAO.shared.nextBatchJobs(category: .Http, limit: 100)
                var ackMessages = [AckMessage]()
                jobs.forEach { (job) in
                    switch job.action {
                    case JobAction.SEND_ACK_MESSAGE.rawValue, JobAction.SEND_DELIVERED_ACK_MESSAGE.rawValue:
                        if let params = job.toBlazeMessage().params, let messageId = params.messageId, let status = params.status {
                            ackMessages.append(AckMessage(jobId: job.jobId, messageId: messageId, status: status))
                        }
                    case JobAction.SEND_ACK_MESSAGES.rawValue:
                        if let messages = job.toBlazeMessage().params?.messages {
                            ackMessages += messages.map { AckMessage(jobId: job.jobId, messageId: $0.messageId, status: $0.status!) }
                        }
                    default:
                        break
                    }
                }
                
                guard ackMessages.count > 0 else {
                    JobDAO.shared.removeJobs(jobIds: jobs.map{ $0.jobId })
                    return
                }
                
                for i in stride(from: 0, to: ackMessages.count, by: 100) {
                    let by = i + 100 > ackMessages.count ? ackMessages.count : i + 100
                    let messages = Array(ackMessages[i..<by])
                    if SendMessageService.shared.sendAckMessages(ackMessages: messages) {
                        JobDAO.shared.removeJobs(jobIds: messages.map{ $0.jobId })
                    } else {
                        return
                    }
                }
            } while true
        }
    }
    
    private func sendAckMessages(ackMessages: [AckMessage]) -> Bool {
        repeat {
            switch MessageAPI.acknowledgements(ackMessages: ackMessages) {
            case .success:
                return true
            case .failure(.unauthorized):
                return false
            case .failure(.forbidden):
                return true
            case .failure:
                checkNetwork()
            }
        } while true
    }
    
    public func processWebSocketMessages() {
        guard !processing else {
            return
        }
        processing = true
        
        dispatchQueue.async {
            defer {
                SendMessageService.shared.processing = false
            }
            var deleteJobId = ""
            repeat {
                guard LoginManager.shared.isLoggedIn else {
                    return
                }
                guard !MixinService.isStopProcessMessages else {
                    return
                }
                guard let job = JobDAO.shared.nextJob(category: .WebSocket) else {
                    return
                }
                
                if job.action == JobAction.SEND_SESSION_MESSAGE.rawValue {
                    guard let sessionId = AppGroupUserDefaults.Account.extensionSession else {
                        JobDAO.shared.removeJob(jobId: job.jobId)
                        continue
                    }
                    let jobs = JobDAO.shared.nextBatchJobs(category: .WebSocket, action: .SEND_SESSION_MESSAGE, limit: 100)
                    let messages: [TransferMessage] = jobs.compactMap {
                        guard let messageId = $0.messageId, let status = $0.status else {
                            return nil
                        }
                        return TransferMessage(messageId: messageId, status: status)
                    }
                    
                    guard messages.count > 0, let conversationId = jobs.first?.conversationId else {
                        JobDAO.shared.removeJobs(jobIds: jobs.map{ $0.jobId })
                        continue
                    }
                    
                    let blazeMessage = BlazeMessage(params: BlazeMessageParam(sessionId: sessionId, conversationId: conversationId, ackMessages: messages), action: BlazeMessageAction.createMessage.rawValue)
                    if SendMessageService.shared.deliverLowPriorityMessages(blazeMessage: blazeMessage) {
                        JobDAO.shared.removeJobs(jobIds: jobs.map{ $0.jobId })
                    }
                } else {
                    if deleteJobId == job.jobId {
                        reporter.report(error: MixinServicesError.duplicatedJob)
                    }
                    guard SendMessageService.shared.handlerJob(job: job) else {
                        return
                    }
                    
                    deleteJobId = job.jobId
                    JobDAO.shared.removeJob(jobId: job.jobId)
                }
            } while true
        }
    }
    
    private func deliverLowPriorityMessages(blazeMessage: BlazeMessage) -> Bool {
        do {
            return try WebSocketService.shared.respondedMessage(for: blazeMessage) != nil
        } catch MixinAPIError.unauthorized {
            return false
        } catch MixinAPIError.forbidden {
            return true
        } catch {
            if let error = error as? MixinAPIError, error.isClientError {
                Thread.sleep(forTimeInterval: 2)
            } else {
                reporter.report(error: error)
            }
            
            while LoginManager.shared.isLoggedIn && (!ReachabilityManger.shared.isReachable || !WebSocketService.shared.isConnected) {
                Thread.sleep(forTimeInterval: 2)
            }
            return false
        }
    }
    
    private func handlerJob(job: Job) -> Bool {
        repeat {
            guard LoginManager.shared.isLoggedIn else {
                return false
            }
            guard !MixinService.isStopProcessMessages else {
                return false
            }
            
            do {
                switch job.action {
                case JobAction.SEND_MESSAGE.rawValue:
                    try ReceiveMessageService.shared.messageDispatchQueue.sync {
                        let blazeMessage = job.toBlazeMessage()
                        if blazeMessage.action == BlazeMessageAction.createCall.rawValue {
                            try SendMessageService.shared.sendCallMessage(blazeMessage: blazeMessage)
                        } else {
                            try SendMessageService.shared.sendMessage(blazeMessage: blazeMessage)
                        }
                    }
                case JobAction.RESEND_MESSAGE.rawValue:
                    try ReceiveMessageService.shared.messageDispatchQueue.sync {
                        try SendMessageService.shared.resendMessage(job: job)
                    }
                case JobAction.SEND_SESSION_MESSAGES.rawValue:
                    deliverNoThrow(blazeMessage: job.toBlazeMessage())
                case JobAction.REFRESH_SESSION.rawValue:
                    _ = ReceiveMessageService.shared.messageDispatchQueue.sync { () -> Bool in
                        let result = refreshParticipantSession(conversationId: job.conversationId!, userId: job.userId!, retry: true)
                        let userInfo = [
                            ReceiveMessageService.UserInfoKey.conversationId: job.conversationId,
                            ReceiveMessageService.UserInfoKey.userId: job.userId
                        ]
                        NotificationCenter.default.post(name: ReceiveMessageService.senderKeyDidChangeNotification, object: self, userInfo: userInfo)
                        return result
                    }
                case JobAction.RESEND_KEY.rawValue:
                    try ReceiveMessageService.shared.messageDispatchQueue.sync {
                        guard let conversationId = job.conversationId, let recipientId = job.userId, let sessionId = job.sessionId else {
                            return
                        }
                        
                        let result = try sendSenderKey(conversationId: conversationId, recipientId: recipientId, sessionId: sessionId)
                        if !result {
                            Logger.write(conversationId: conversationId, log: "[ResendSenderKey]...recipientId:\(recipientId)...No any group signal key from server")
                            sendNoKeyMessage(conversationId: conversationId, recipientId: recipientId)
                        }
                    }
                case JobAction.REQUEST_RESEND_KEY.rawValue:
                    ReceiveMessageService.shared.messageDispatchQueue.sync {
                        let blazeMessage = job.toBlazeMessage()
                        deliverNoThrow(blazeMessage: blazeMessage)
                        Logger.write(conversationId: job.conversationId!, log: "[SendMessageService][REQUEST_RESEND_KEY]...messageId:\(blazeMessage.params?.messageId ?? "")")
                    }
                case JobAction.REQUEST_RESEND_MESSAGES.rawValue:
                    deliverNoThrow(blazeMessage: job.toBlazeMessage())
                case JobAction.SEND_NO_KEY.rawValue:
                    deliverNoThrow(blazeMessage: job.toBlazeMessage())
                default:
                    break
                }
                return true
            } catch {
                checkNetworkAndWebSocket()
                if let error = error as? MixinAPIError, error.isTransportTimedOut {
                    
                } else {
                    var blazeMessage = ""
                    var conversationId = job.conversationId ?? ""
                    if let bm = job.blazeMessage {
                        blazeMessage = String(data: bm, encoding: .utf8) ?? ""
                        if conversationId.isEmpty {
                            conversationId = job.toBlazeMessage().params?.conversationId ?? ""
                        }
                    }
                    
                    var userInfo = [String: Any]()
                    userInfo["errorCode"] = (error as NSError).code
                    userInfo["errorDescription"] = error.localizedDescription
                    userInfo["JobAction"] = job.action
                    userInfo["conversationId"] = conversationId
                    if !conversationId.isEmpty && job.action == JobAction.SEND_MESSAGE.rawValue {
                        if let conversationName = ConversationDAO.shared.getConversation(conversationId: conversationId)?.name {
                            userInfo["conversationName"] = conversationName
                        }
                    }
                    userInfo["blazeMessage"] = blazeMessage
                    if let err = error as? SignalError {
                        userInfo["signalErrorCode"] = err.rawValue
                        if IdentityDAO.shared.getLocalIdentity() == nil {
                            userInfo["signalError"] = "local identity nil"
                            userInfo["identityCount"] = "\(IdentityDAO.shared.getCount())"
                            Logger.write(error: error, userInfo: userInfo)
                            reporter.report(error: MixinServicesError.sendMessage(userInfo))
                            LoginManager.shared.logout(from: "SendMessengerError")
                            return false
                        }
                    }
                    Logger.write(error: error, userInfo: userInfo)
                    reporter.report(error: MixinServicesError.sendMessage(userInfo))
                }
                
                if case MixinAPIError.invalidRequestData = error {
                    return true
                }
            }
        } while true
    }
}

extension SendMessageService {
    
    // When a text message is sent to group with format "^@700\d* ", it will be send directly to the app if the app is in the group
    public func willTextMessageWithContentSendDirectlyToApp(_ content: String, conversationId: String, inGroup: Bool) -> Bool {
        guard inGroup else {
            return false
        }
        guard let identityNumber = prefixMentionedAppIdentityNumberFromMessage(with: content) else {
            return false
        }
        if let recipientId = ParticipantDAO.shared.getParticipantId(conversationId: conversationId, identityNumber: identityNumber) {
            return !recipientId.isEmpty
        } else {
            return false
        }
    }
    
    private func prefixMentionedAppIdentityNumberFromMessage(with content: String) -> String? {
        guard content.hasPrefix("@700"), let botNumberRange = content.range(of: #"^@700\d* "#, options: .regularExpression) else {
            return nil
        }
        return content[botNumberRange].dropFirstAndLast()
    }
    
    private func resendMessage(job: Job) throws {
        var blazeMessage = job.toBlazeMessage()
        guard let messageId = blazeMessage.params?.messageId, let resendMessageId = job.resendMessageId, let recipientId = job.userId else {
            return
        }
        guard let message = MessageDAO.shared.getMessage(messageId: messageId), try checkSignalSession(recipientId: recipientId, sessionId: job.sessionId) else {
            return
        }
        
        blazeMessage.params?.category = message.category
        blazeMessage.params?.messageId = resendMessageId
        blazeMessage.params?.quoteMessageId = message.quoteMessageId
        blazeMessage.params?.data = try SignalProtocol.shared.encryptSessionMessageData(recipientId: recipientId, content: message.content ?? "", resendMessageId: messageId, sessionId: job.sessionId)
        try deliverMessage(blazeMessage: blazeMessage)
        
        Logger.write(conversationId: message.conversationId, log: "[SendMessageService][ResendMessage]...messageId:\(messageId)...resendMessageId:\(resendMessageId)...resendUserId:\(recipientId)")
    }
    
    private func sendMessage(blazeMessage: BlazeMessage) throws {
        var blazeMessage = blazeMessage
        guard let messageId = blazeMessage.params?.messageId, var message = MessageDAO.shared.getMessage(messageId: messageId) else {
            return
        }
        guard let conversation = ConversationDAO.shared.getConversation(conversationId: message.conversationId) else {
            return
        }
        
        if conversation.isGroup() && conversation.status != ConversationStatus.SUCCESS.rawValue {
            var userInfo = [String: Any]()
            userInfo["error"] = "conversation status error"
            userInfo["conversationStatus"] = "\(conversation.status)"
            userInfo["conversationId"] = "\(message.conversationId)"
            reporter.report(error: MixinServicesError.sendMessage(userInfo))
            return
        }
        
        if message.category.hasSuffix("_TEXT"), let text = message.content {
            if conversation.category == ConversationCategory.GROUP.rawValue, let identityNumber = prefixMentionedAppIdentityNumberFromMessage(with: text) {
                if let recipientId = ParticipantDAO.shared.getParticipantId(conversationId: conversation.conversationId, identityNumber: identityNumber), !recipientId.isEmpty {
                    blazeMessage.params?.recipientId = recipientId
                    blazeMessage.params?.data = nil
                } else {
                    message.category = MessageCategory.SIGNAL_TEXT.rawValue
                }
            } else {
                let numbers = MessageMentionDetector.identityNumbers(from: text).filter { $0 != myIdentityNumber }
                if numbers.count > 0 {
                    let userIds = UserDAO.shared.userIds(identityNumbers: numbers)
                    blazeMessage.params?.mentions = userIds
                }
            }
        }
        
        if message.category == MessageCategory.MESSAGE_RECALL.rawValue {
            blazeMessage.params?.messageId = UUID().uuidString.lowercased()
        } else {
            blazeMessage.params?.category = message.category
            blazeMessage.params?.quoteMessageId = message.quoteMessageId
        }
        
        if message.category.hasPrefix("PLAIN_") || message.category == MessageCategory.MESSAGE_RECALL.rawValue || message.category == MessageCategory.APP_CARD.rawValue {
            try checkConversationExist(conversation: conversation)
            if blazeMessage.params?.data == nil {
                let needsEncodeCategories: [MessageCategory] = [
                    .PLAIN_TEXT, .PLAIN_POST, .PLAIN_LOCATION, .PLAIN_TRANSCRIPT
                ]
                if needsEncodeCategories.map(\.rawValue).contains(message.category) {
                    blazeMessage.params?.data = message.content?.base64Encoded()
                } else {
                    blazeMessage.params?.data = message.content
                }
            }
        } else {
            if !SignalProtocol.shared.isExistSenderKey(groupId: message.conversationId, senderId: message.userId) {
                if conversation.isGroup() {
                    syncConversation(conversationId: message.conversationId)
                } else {
                    try createConversation(conversation: conversation)
                }
            }
            try checkSessionSenderKey(conversationId: message.conversationId)
            
            let content = blazeMessage.params?.data ?? message.content ?? ""
            blazeMessage.params?.data = try SignalProtocol.shared.encryptGroupMessageData(conversationId: message.conversationId, senderId: message.userId, content: content)
        }
        
        try deliverMessage(blazeMessage: blazeMessage)
        Logger.write(conversationId: message.conversationId, log: "[SendMessageService][SendMessage][\(message.category)]...messageId:\(messageId)...messageStatus:\(message.status)")
    }
    
    private func checkConversationExist(conversation: ConversationItem) throws {
        guard conversation.status == ConversationStatus.START.rawValue else {
            return
        }
        
        try createConversation(conversation: conversation)
    }
    
    private func createConversation(conversation: ConversationItem) throws {
        var participants: [ParticipantRequest]
        if conversation.category == ConversationCategory.CONTACT.rawValue {
            participants = [ParticipantRequest(userId: conversation.ownerId, role: "")]
        } else {
            participants = ParticipantDAO.shared.participantRequests(conversationId: conversation.conversationId, currentAccountId: currentAccountId)
        }
        let request = ConversationRequest(conversationId: conversation.conversationId, name: nil, category: conversation.category, participants: participants, duration: nil, announcement: nil)
        switch ConversationAPI.createConversation(conversation: request) {
        case let .success(response):
            ConversationDAO.shared.createConversation(conversation: response, targetStatus: .SUCCESS)
        case let .failure(error):
            throw error
        }
    }
    
    private func sendCallMessage(blazeMessage: BlazeMessage) throws {
        guard let params = blazeMessage.params else {
            return
        }
        guard let categoryString = params.category, let category = MessageCategory(rawValue: categoryString) else {
            return
        }
        guard MixinService.callMessageCoordinator.shouldSendRtcBlazeMessage(with: category) else {
            return
        }
        guard let conversationId = params.conversationId else {
            return
        }
        guard let conversation = ConversationDAO.shared.getConversation(conversationId: conversationId) else {
            return
        }
        try checkConversationExist(conversation: conversation)
        try deliverMessage(blazeMessage: blazeMessage)
    }
    
    private func deliverMessage(blazeMessage: BlazeMessage) throws {
        do {
            try deliver(blazeMessage: blazeMessage)
        } catch MixinAPIError.forbidden {
            #if DEBUG
            print("\(MixinAPIError.forbidden)")
            #endif
        } catch {
            #if DEBUG
            print(error)
            #endif
            throw error
        }
    }
    
}
