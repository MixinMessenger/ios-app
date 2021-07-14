import Foundation
import UserNotifications
import UIKit
import MixinServices

class RequestInAppNotificationJob: BaseJob {
    
    let message: MessageItem
    let isSilent: Bool
    
    init?(message: MessageItem, silent: Bool) {
        guard message.status == MessageStatus.DELIVERED.rawValue else {
            return nil
        }
        guard message.userId != myUserId else {
            return nil
        }
        let availableCategorySuffices = ["_TEXT", "_IMAGE", "_STICKER", "_CONTACT", "_DATA", "_VIDEO", "_LIVE", "_AUDIO", "_POST", "_LOCATION", "_TRANSCRIPT"]
        let isCategoryAvailable = availableCategorySuffices.contains(where: message.category.hasSuffix(_:))
            || ["SYSTEM_ACCOUNT_SNAPSHOT"].contains(message.category)
        guard isCategoryAvailable else {
            return nil
        }
        self.message = message
        self.isSilent = silent
    }
    
    override func getJobId() -> String {
        return "show-notification-\(message.messageId)"
    }
    
    override func main() {
        let message = self.message
        guard let conversation = ConversationDAO.shared.getConversation(conversationId: message.conversationId), conversation.status == ConversationStatus.SUCCESS.rawValue else {
            return
        }
        
        let isMentioned = message.mentions?[myIdentityNumber] != nil
        guard !conversation.isMuted || isMentioned else {
            return
        }
        
        var ownerUser: UserItem?
        if conversation.category == ConversationCategory.CONTACT.rawValue {
            guard let user = UserDAO.shared.getUser(userId: message.userId) else {
                return
            }
            if LoginManager.shared.account?.receive_message_source == ReceiveMessageSource.contacts.rawValue && user.relationship != Relationship.FRIEND.rawValue {
                return
            }
            ownerUser = user
        }
        
        DispatchQueue.main.sync {
            guard message.conversationId != UIApplication.currentConversationId() else {
                return
            }
            
            AppDelegate.current.updateApplicationIconBadgeNumber()
            let content = UNMutableNotificationContent(message: message, ownerUser: ownerUser, conversation: conversation, silent: isSilent)
            let request = UNNotificationRequest(identifier: message.messageId, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }
    
}
