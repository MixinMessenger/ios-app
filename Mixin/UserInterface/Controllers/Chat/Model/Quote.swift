import UIKit

struct Quote {
    
    static let jsonDecoder = JSONDecoder()

    enum Image {
        case url(URL)
        case user(urlString: String, identityNumber: String, name: String)
        case thumbnail(UIImage)
    }
    
    let title: String
    let tintColor: UIColor
    let icon: UIImage?
    let subtitle: String
    let image: Image?
    
    init?(quoteContent: Data) {
        guard let message = try? Quote.jsonDecoder.decode(MessageItem.self, from: quoteContent) else {
            return nil
        }
        title = message.userFullName
        if let identityNumber = Int(message.userIdentityNumber) {
            tintColor = UIColor.usernameColors[identityNumber % UIColor.usernameColors.count]
        } else {
            tintColor = .black
        }
        icon = MessageCategory.iconImage(forMessageCategoryString: message.category)
        subtitle = message.quoteSubtitle
        
        var image: Image?
        if message.mediaStatus == MediaStatus.DONE.rawValue {
            if message.category.hasSuffix("_IMAGE"), let mediaUrl = message.mediaUrl, !mediaUrl.isEmpty {
                let url = MixinFile.url(ofChatDirectory: .photos, filename: mediaUrl)
                image = .url(url)
            } else if message.category.hasSuffix("_VIDEO"), let mediaUrl = message.mediaUrl, let filename = mediaUrl.components(separatedBy: ".").first {
                let betterThumbnailFilename = filename + ExtensionName.jpeg.withDot
                let url = MixinFile.url(ofChatDirectory: .videos, filename: betterThumbnailFilename)
                image = .url(url)
            }
        } else if message.category.hasSuffix("_STICKER"), let assetUrl = message.assetUrl, let url = URL(string: assetUrl) {
            image = .url(url)
        } else if message.category.hasSuffix("_CONTACT") {
            image = .user(urlString: message.sharedUserAvatarUrl, identityNumber: message.sharedUserIdentityNumber, name: message.sharedUserFullName)
        }
        if image == nil, let thumbnail = Quote.image(from: message.thumbImage) {
            image = .thumbnail(thumbnail)
        }
        self.image = image
    }
    
    static func image(from str: String?) -> UIImage? {
        guard let str = str, let data = Data(base64Encoded: str) else {
            return nil
        }
        return UIImage(data: data)
    }
    
}
