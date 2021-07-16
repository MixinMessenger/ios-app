import UserNotifications
import MixinServices

final class NotificationService: UNNotificationServiceExtension {
    
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var rawContent: UNNotificationContent?
    private var isExpired = false
    private var conversationId: String?
    private var messageId = ""
    private static var isInitiatedReporter = false

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        self.rawContent = request.content
        self.messageId = request.content.userInfo["message_id"] as? String ?? ""
        self.conversationId = request.content.userInfo["conversation_id"] as? String

        guard !messageId.isEmpty else {
            deliverRawContent(from: "notification data broken")
            return
        }
        guard canProcessMessages else {
            deliverRawContent(from: "can't process messages")
            return
        }
        guard !AppGroupUserDefaults.isRunningInMainApp else {
            deliverRawContent(from: "main app is running")
            return
        }

        initReporter()
        _ = DarwinNotificationManager.shared
        _ = ReachabilityManger.shared
        MixinService.callMessageCoordinator = CallMessageSaver.shared
        
        ReceiveMessageService.shared.processReceiveMessage(messageId: messageId, conversationId: conversationId, extensionTimeWillExpire: { [weak self]() -> Bool in
            return self?.isExpired ?? true
        }) { [weak self](messageItem) in
            guard let weakSelf = self else {
                return
            }
            if let message = messageItem {
                weakSelf.deliverNotification(with: message)
            } else {
                weakSelf.deliverRawContent(from: "no message")
            }
        }
    }

    override func serviceExtensionTimeWillExpire() {
        isExpired = true
        deliverRawContent(from: "serviceExtensionTimeWillExpire")
    }

    private func initReporter() {
        guard !Self.isInitiatedReporter else {
            return
        }
        Self.isInitiatedReporter = true
        reporter.configure()
        reporter.registerUserInformation()
    }

    private func deliverNotification(with message: MessageItem) {
        guard message.status != MessageStatus.FAILED.rawValue else {
            deliverRawContent(from: "message status failed")
            return
        }
        guard let conversation = ConversationDAO.shared.getConversation(conversationId: message.conversationId) else {
            deliverRawContent(from: "no conversation")
            return
        }
        let ownerUser: UserItem?
        if conversation.category == ConversationCategory.CONTACT.rawValue {
            ownerUser = UserDAO.shared.getUser(userId: message.userId)
        } else {
            ownerUser = nil
        }
        let content = UNMutableNotificationContent(message: message, ownerUser: ownerUser, conversation: conversation, silent: rawContent?.sound == nil)
        deliverContent(content: content)
    }
    
    private func deliverRawContent(from: String) {
        guard let rawContent = rawContent else {
            return
        }
        deliverContent(content: rawContent)

        if let conversationId = self.conversationId {
            Logger.write(conversationId: conversationId, log: """
                [\(messageId)]...\(from)...isExpired:\(isExpired)...
                isLoggedIn:\(LoginManager.shared.isLoggedIn)]...
                isDocumentsMigrated:\(AppGroupUserDefaults.isDocumentsMigrated)]...
                needsUpgradeInMainApp:\(AppGroupUserDefaults.User.needsUpgradeInMainApp)]...
                isProcessingMessagesInAppExtension:\(AppGroupUserDefaults.isProcessingMessagesInAppExtension)]...
                isRunningInMainApp:\(AppGroupUserDefaults.isRunningInMainApp)]...
            """)
        }
    }
    
    private func deliverContent(content: UNNotificationContent?) {
        guard let content = content else {
            return
        }
        guard canProcessMessages else {
            contentHandler?(content)
            return
        }
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = content.title
        notificationContent.subtitle = content.subtitle
        notificationContent.body = content.body
        notificationContent.userInfo = content.userInfo
        notificationContent.sound = content.sound
        notificationContent.categoryIdentifier = content.categoryIdentifier
        notificationContent.threadIdentifier = content.threadIdentifier
        notificationContent.attachments = content.attachments
        notificationContent.badge = NSNumber(value: ConversationDAO.shared.getUnreadMessageCountWithoutMuted())
        
        contentHandler?(notificationContent)
    }
    
}
