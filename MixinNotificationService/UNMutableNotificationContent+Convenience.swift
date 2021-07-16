import Foundation
import UserNotifications
import MixinServices

public extension UNMutableNotificationContent {
    
    convenience init(message: MessageItem, ownerUser: UserItem?, conversation: ConversationItem, silent: Bool) {
        self.init()
        
        let conversationIsGroup = conversation.isGroup()
        let isRepresentativeMessage = message.isRepresentativeMessage(conversation: conversation)
        
        if conversationIsGroup {
            title = conversation.name
        } else if isRepresentativeMessage {
            title = conversation.ownerFullName
        } else {
            title = message.userFullName ?? ""
        }
        
        if AppGroupUserDefaults.User.showMessagePreviewInNotification {
            body = messagePreview(conversationIsGroup: conversationIsGroup,
                                  isRepresentativeMessage: isRepresentativeMessage,
                                  message: message)
        } else {
            body = R.string.localizable.notification_content_general()
        }
        
        userInfo[UserInfoKey.conversationId] = conversation.conversationId
        userInfo[UserInfoKey.conversationCategory] = conversation.category
        userInfo[UserInfoKey.messageId] = message.messageId
        ownerUser?.notificationUserInfo.forEach({ (key, value) in
            userInfo[key] = value
        })
        
        sound = silent ? nil : .mixin
        categoryIdentifier = NotificationCategoryIdentifier.message
        threadIdentifier = conversation.conversationId
    }
    
    private func messagePreview(conversationIsGroup: Bool, isRepresentativeMessage: Bool, message: MessageItem) -> String {
        let userFullName = message.userFullName ?? ""
        if message.category.hasSuffix("_TEXT") {
            if conversationIsGroup || isRepresentativeMessage {
                return "\(userFullName): \(message.mentionedFullnameReplacedContent)"
            } else {
                return message.mentionedFullnameReplacedContent
            }
        } else if message.category.hasSuffix("_IMAGE") {
            if conversationIsGroup || isRepresentativeMessage {
                return R.string.localizable.alert_key_group_image_message(userFullName)
            } else {
                return R.string.localizable.alert_key_contact_image_message()
            }
        } else if message.category.hasSuffix("_VIDEO") {
            if conversationIsGroup || isRepresentativeMessage {
                return R.string.localizable.alert_key_group_video_message(userFullName)
            } else {
                return R.string.localizable.alert_key_contact_video_message()
            }
        } else if message.category.hasSuffix("_LIVE") {
            if conversationIsGroup || isRepresentativeMessage {
                return R.string.localizable.alert_key_group_live_message(userFullName)
            } else {
                return R.string.localizable.alert_key_contact_live_message()
            }
        } else if message.category.hasSuffix("_AUDIO") {
            if conversationIsGroup || isRepresentativeMessage {
                return R.string.localizable.alert_key_group_audio_message(userFullName)
            } else {
                return R.string.localizable.alert_key_contact_audio_message()
            }
        } else if message.category.hasSuffix("_DATA") {
            if conversationIsGroup || isRepresentativeMessage {
                return R.string.localizable.alert_key_group_data_message(userFullName)
            } else {
                return R.string.localizable.alert_key_contact_data_message()
            }
        } else if message.category.hasSuffix("_STICKER") {
            if conversationIsGroup || isRepresentativeMessage {
                return R.string.localizable.alert_key_group_sticker_message(userFullName)
            } else {
                return R.string.localizable.alert_key_contact_sticker_message()
            }
        } else if message.category.hasSuffix("_CONTACT") {
            if conversationIsGroup || isRepresentativeMessage {
                return R.string.localizable.alert_key_group_contact_message(userFullName)
            } else {
                return R.string.localizable.alert_key_contact_contact_message()
            }
        } else if message.category.hasSuffix("_POST") {
            if conversationIsGroup || isRepresentativeMessage {
                return "\(userFullName): \(message.markdownControlCodeRemovedContent)"
            } else {
                return message.markdownControlCodeRemovedContent
            }
        } else if message.category.hasSuffix("_LOCATION") {
            if conversationIsGroup || isRepresentativeMessage {
                return R.string.localizable.alert_key_group_location_message(userFullName)
            } else {
                return R.string.localizable.alert_key_contact_location_message()
            }
        } else if message.category.hasPrefix("KRAKEN_") {
            return R.string.localizable.alert_key_group_audio_invite_message(userFullName)
        } else if message.category == MessageCategory.SYSTEM_ACCOUNT_SNAPSHOT.rawValue {
            switch message.snapshotType {
            case SnapshotType.deposit.rawValue:
                return R.string.localizable.notification_content_deposit()
            case SnapshotType.transfer.rawValue:
                return R.string.localizable.alert_key_contact_transfer_message()
            case SnapshotType.withdrawal.rawValue:
                return R.string.localizable.notification_content_withdrawal()
            case SnapshotType.fee.rawValue:
                return R.string.localizable.notification_content_fee()
            case SnapshotType.rebate.rawValue:
                return R.string.localizable.notification_content_rebate()
            default:
                return R.string.localizable.notification_content_general()
            }
        } else if message.category == MessageCategory.WEBRTC_AUDIO_OFFER.rawValue {
            return R.string.localizable.alert_key_contact_audio_call_message()
        } else if message.category == MessageCategory.WEBRTC_AUDIO_CANCEL.rawValue {
            return R.string.localizable.alert_key_contact_audio_call_cancelled_message()
        } else if message.category.hasSuffix("_TRANSCRIPT") {
            if conversationIsGroup || isRepresentativeMessage {
                return R.string.localizable.alert_key_group_transcript_message(userFullName)
            } else {
                return R.string.localizable.alert_key_contact_transcript_message()
            }
        } else {
            return R.string.localizable.notification_content_general()
        }
    }
    
}
