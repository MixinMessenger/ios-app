import Foundation
import MixinServices

extension Message {
    
    static func createMessage(context: ExternalSharingContext) -> Message {
        var message = Message.createMessage(messageId: UUID().uuidString.lowercased(),
                                            conversationId: context.conversationId ?? "",
                                            userId: myUserId,
                                            category: "",
                                            status: MessageStatus.SENDING.rawValue,
                                            createdAt: Date().toUTCString())
        switch context.content {
        case .text(let text):
            message.category = MessageCategory.SIGNAL_TEXT.rawValue
            message.content = text
        case .image:
            message.category = MessageCategory.SIGNAL_IMAGE.rawValue
            message.mediaStatus = MediaStatus.PENDING.rawValue
        case .live(let data):
            message.category = MessageCategory.SIGNAL_LIVE.rawValue
            message.mediaUrl = data.url
            message.mediaWidth = data.width
            message.mediaHeight = data.height
            message.thumbUrl = data.thumbUrl
            let data = try! JSONEncoder.default.encode(data)
            message.content = String(data: data, encoding: .utf8)
        case .contact(let data):
            message.category = MessageCategory.SIGNAL_CONTACT.rawValue
            message.sharedUserId = data.userId
            message.content = try! JSONEncoder.default.encode(data).base64EncodedString()
        case .post(let text):
            message.category = MessageCategory.SIGNAL_POST.rawValue
            message.content = text
        case .appCard(let data):
            message.category = MessageCategory.APP_CARD.rawValue
            message.content = try! JSONEncoder.default.encode(data).base64EncodedString()
        }
        return message
    }
    
}
