import Foundation
import MixinServices

extension SendMessageService {
    
    func sendMessage(message: Message, children: [TranscriptMessage]? = nil, ownerUser: UserItem?, isGroupMessage: Bool, silentNotification: Bool = false) {
        guard let account = LoginManager.shared.account else {
            return
        }

        var msg = message
        msg.userId = account.user_id
        msg.status = MessageStatus.SENDING.rawValue

        var isSignalMessage = isGroupMessage
        if !isGroupMessage {
            isSignalMessage = !(ownerUser?.isBot ?? true)
        }

        if msg.category.hasSuffix("_TEXT") {
            if isSignalMessage {
                if let content = msg.content, willTextMessageWithContentSendDirectlyToApp(content, conversationId: msg.conversationId, inGroup: isGroupMessage) {
                    msg.category = MessageCategory.PLAIN_TEXT.rawValue
                } else {
                    msg.category = MessageCategory.SIGNAL_TEXT.rawValue
                }
            } else {
                msg.category = MessageCategory.PLAIN_TEXT.rawValue
            }
        } else if msg.category.hasSuffix("_IMAGE") {
            msg.category = isSignalMessage ? MessageCategory.SIGNAL_IMAGE.rawValue :  MessageCategory.PLAIN_IMAGE.rawValue
        } else if msg.category.hasSuffix("_VIDEO") {
            msg.category = isSignalMessage ? MessageCategory.SIGNAL_VIDEO.rawValue :  MessageCategory.PLAIN_VIDEO.rawValue
        } else if msg.category.hasSuffix("_DATA") {
            msg.category = isSignalMessage ? MessageCategory.SIGNAL_DATA.rawValue :  MessageCategory.PLAIN_DATA.rawValue
        } else if msg.category.hasSuffix("_STICKER") {
            msg.category = isSignalMessage ? MessageCategory.SIGNAL_STICKER.rawValue :  MessageCategory.PLAIN_STICKER.rawValue
        } else if msg.category.hasSuffix("_CONTACT") {
            msg.category = isSignalMessage ? MessageCategory.SIGNAL_CONTACT.rawValue :  MessageCategory.PLAIN_CONTACT.rawValue
        } else if msg.category.hasSuffix("_AUDIO") {
            msg.category = isSignalMessage ? MessageCategory.SIGNAL_AUDIO.rawValue :  MessageCategory.PLAIN_AUDIO.rawValue
        } else if msg.category.hasSuffix("_LIVE") {
            msg.category = isSignalMessage ? MessageCategory.SIGNAL_LIVE.rawValue :  MessageCategory.PLAIN_LIVE.rawValue
        } else if msg.category.hasSuffix("_POST") {
            msg.category = isSignalMessage ? MessageCategory.SIGNAL_POST.rawValue :  MessageCategory.PLAIN_POST.rawValue
        } else if msg.category.hasSuffix("_LOCATION") {
            msg.category = isSignalMessage ? MessageCategory.SIGNAL_LOCATION.rawValue :  MessageCategory.PLAIN_LOCATION.rawValue
        } else if msg.category.hasSuffix("_TRANSCRIPT") {
            msg.category = isSignalMessage ? MessageCategory.SIGNAL_TRANSCRIPT.rawValue :  MessageCategory.PLAIN_TRANSCRIPT.rawValue
            for child in children ?? [] {
                let category = child.category
                if isSignalMessage, category.hasPrefix("PLAIN_") {
                    let range = category.startIndex...category.index(category.startIndex, offsetBy: 5)
                    child.category.replaceSubrange(range, with: "SIGNAL_")
                    child.mediaCreatedAt = nil // Force attachement to re-upload
                } else if !isSignalMessage, category.hasPrefix("SIGNAL_") {
                    let range = category.startIndex...category.index(category.startIndex, offsetBy: 6)
                    child.category.replaceSubrange(range, with: "PLAIN_")
                    child.mediaCreatedAt = nil // Force attachement to re-upload
                }
            }
        }

        jobCreationQueue.async {
            if msg.conversationId.isEmpty || !ConversationDAO.shared.isExist(conversationId: msg.conversationId) {
                guard let user = ownerUser else {
                    return
                }
                let conversationId = ConversationDAO.shared.makeConversationId(userId: account.user_id, ownerUserId: user.userId)
                msg.conversationId = conversationId
                ConversationDAO.shared.createConversation(conversation: ConversationResponse(conversationId: conversationId, userId: user.userId, avatarUrl: user.avatarUrl), targetStatus: .START)
            }
            
            if message.category.hasPrefix("WEBRTC_") {
                guard let recipient = ownerUser else {
                    Logger.write(log: "[Call] recipient user id is empty!")
                    return
                }
                SendMessageService.shared.sendWebRTCMessage(message: message, recipientId: recipient.userId)
            } else {
                if let content = msg.content, ["_TEXT", "_POST"].contains(where: msg.category.hasSuffix), content.utf8.count > maxTextMessageContentLength {
                    msg.content = String(content.prefix(maxTextMessageContentLength))
                }
                MessageDAO.shared.insertMessage(message: msg, children: children, messageSource: "") {
                    if ["_TEXT", "_POST", "_STICKER", "_CONTACT", "_LIVE", "_LOCATION"].contains(where: msg.category.hasSuffix) || msg.category == MessageCategory.APP_CARD.rawValue {
                        SendMessageService.shared.sendMessage(message: msg, data: msg.content, silentNotification: silentNotification)
                    } else if msg.category.hasSuffix("_IMAGE") {
                        let jobId = SendMessageService.shared.saveUploadJob(message: msg)
                        UploaderQueue.shared.addJob(job: ImageUploadJob(message: msg, jobId: jobId))
                    } else if msg.category.hasSuffix("_VIDEO") {
                        let jobId = SendMessageService.shared.saveUploadJob(message: msg)
                        UploaderQueue.shared.addJob(job: VideoUploadJob(message: msg, jobId: jobId))
                    } else if msg.category.hasSuffix("_DATA") {
                        let jobId = SendMessageService.shared.saveUploadJob(message: msg)
                        UploaderQueue.shared.addJob(job: FileUploadJob(message: msg, jobId: jobId))
                    } else if msg.category.hasSuffix("_AUDIO") {
                        let jobId = SendMessageService.shared.saveUploadJob(message: msg)
                        UploaderQueue.shared.addJob(job: AudioUploadJob(message: msg, jobId: jobId))
                    } else if msg.category.hasSuffix("_TRANSCRIPT") {
                        let jobId = SendMessageService.shared.saveUploadJob(message: msg)
                        let job = TranscriptAttachmentUploadJob(message: msg,
                                                                jobIdToRemoveAfterFinished: jobId)
                        UploaderQueue.shared.addJob(job: job)
                    }
                }
            }
        }
    }
    
}
