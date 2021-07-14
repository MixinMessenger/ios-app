import Foundation
import Photos
import MixinServices

final class ConversationMessageComposer {
    
    let queue: DispatchQueue
    let conversationId: String
    let isGroup: Bool
    let ownerUser: UserItem?
    
    private lazy var thumbnailRequestOptions: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.isSynchronous = true
        return options
    }()
    
    init(queue: DispatchQueue, conversationId: String, isGroup: Bool, ownerUser: UserItem?) {
        self.queue = queue
        self.conversationId = conversationId
        self.isGroup = isGroup
        self.ownerUser = ownerUser
    }
    
    convenience init(dataSource: ConversationDataSource, ownerUser: UserItem?) {
        self.init(queue: dataSource.queue,
                  conversationId: dataSource.conversationId,
                  isGroup: dataSource.category == .group,
                  ownerUser: ownerUser)
    }
    
    func sendMessage(type: MessageCategory, messageId: String? = nil, quote: MessageItem? = nil, value: Any, silentNotification: Bool = false) {
        let isGroupMessage = self.isGroup
        let ownerUser = self.ownerUser
        let createdAt: Date = {
            var date = Date()
            if let quote = quote {
                let quoteDate = quote.createdAt.toUTCDate()
                if quoteDate > date {
                    date = quoteDate.addingTimeInterval(0.001)
                }
            }
            return date
        }()
        var message = Message.createMessage(category: type.rawValue,
                                            conversationId: conversationId,
                                            createdAt: createdAt.toUTCString(),
                                            userId: myUserId)
        message.quoteMessageId = quote?.messageId
        if let messageId = messageId {
            message.messageId = messageId
        }
        if type == .SIGNAL_TEXT || type == .SIGNAL_POST, let text = value as? String {
            message.content = text
            queue.async {
                SendMessageService.shared.sendMessage(message: message, ownerUser: ownerUser, isGroupMessage: isGroupMessage, silentNotification: silentNotification)
            }
        } else if type == .SIGNAL_DATA, let url = value as? URL {
            queue.async {
                guard FileManager.default.fileSize(url.path) > 0 else {
                    showAutoHiddenHud(style: .error, text: R.string.localizable.error_operation_failed())
                    return
                }
                let fileExtension = url.pathExtension.lowercased()
                let targetUrl = AttachmentContainer.url(for: .files, filename: "\(message.messageId).\(fileExtension)")
                do {
                    try FileManager.default.copyItem(at: url, to: targetUrl)
                } catch {
                    showAutoHiddenHud(style: .error, text: R.string.localizable.error_operation_failed())
                    return
                }
                message.name = url.lastPathComponent
                message.mediaSize = FileManager.default.fileSize(targetUrl.path)
                message.mediaMimeType = FileManager.default.mimeType(ext: fileExtension)
                message.mediaUrl = targetUrl.lastPathComponent
                message.mediaStatus = MediaStatus.PENDING.rawValue
                SendMessageService.shared.sendMessage(message: message, ownerUser: ownerUser, isGroupMessage: isGroupMessage)
            }
        } else if type == .SIGNAL_VIDEO, let url = value as? URL {
            queue.async {
                let asset = AVAsset(url: url)
                guard asset.duration.isValid, let videoTrack = asset.tracks(withMediaType: .video).first else {
                    showAutoHiddenHud(style: .error, text: R.string.localizable.error_operation_failed())
                    return
                }
                if let thumbnail = UIImage(withFirstFrameOfVideoAtURL: url) {
                    let thumbnailURL = AttachmentContainer.videoThumbnailURL(videoFilename: url.lastPathComponent)
                    thumbnail.saveToFile(path: thumbnailURL)
                    message.thumbImage = thumbnail.base64Thumbnail()
                } else {
                    showAutoHiddenHud(style: .error, text: R.string.localizable.error_operation_failed())
                    return
                }
                message.mediaDuration = Int64(asset.duration.seconds * millisecondsPerSecond)
                let size = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
                message.mediaWidth = Int(abs(size.width))
                message.mediaHeight = Int(abs(size.height))
                message.mediaSize = FileManager.default.fileSize(url.path)
                message.mediaMimeType = FileManager.default.mimeType(ext: url.pathExtension)
                message.mediaUrl = url.lastPathComponent
                message.mediaStatus = MediaStatus.PENDING.rawValue
                SendMessageService.shared.sendMessage(message: message, ownerUser: ownerUser, isGroupMessage: isGroupMessage)
            }
        } else if type == .SIGNAL_AUDIO, let value = value as? (tempUrl: URL, metadata: AudioMetadata) {
            queue.async {
                guard FileManager.default.fileSize(value.tempUrl.path) > 0 else {
                    showAutoHiddenHud(style: .error, text: R.string.localizable.error_operation_failed())
                    return
                }
                let url = AttachmentContainer.url(for: .audios, filename: message.messageId + ExtensionName.ogg.withDot)
                do {
                    try FileManager.default.moveItem(at: value.tempUrl, to: url)
                    message.mediaSize = FileManager.default.fileSize(url.path)
                    message.mediaMimeType = FileManager.default.mimeType(ext: url.pathExtension)
                    message.mediaUrl = url.lastPathComponent
                    message.mediaStatus = MediaStatus.PENDING.rawValue
                    message.mediaWaveform = value.metadata.waveform
                    message.mediaDuration = Int64(value.metadata.duration)
                    SendMessageService.shared.sendMessage(message: message, ownerUser: ownerUser, isGroupMessage: isGroupMessage)
                } catch {
                    showAutoHiddenHud(style: .error, text: R.string.localizable.error_operation_failed())
                }
            }
        } else if type == .SIGNAL_STICKER, let sticker = value as? StickerItem {
            message.mediaStatus = MediaStatus.PENDING.rawValue
            message.mediaUrl = sticker.assetUrl
            message.stickerId = sticker.stickerId
            queue.async {
                reporter.report(event: .sendSticker, userInfo: ["stickerId": sticker.stickerId])
                let albumId = AlbumDAO.shared.getAlbum(stickerId: sticker.stickerId)?.albumId
                let transferData = TransferStickerData(stickerId: sticker.stickerId, name: sticker.name, albumId: albumId)
                message.content = try! JSONEncoder().encode(transferData).base64EncodedString()
                SendMessageService.shared.sendMessage(message: message, ownerUser: ownerUser, isGroupMessage: isGroupMessage)
            }
        }
    }
    
    func send(image: GiphyImage, thumbnail: UIImage?) {
        let conversationId = self.conversationId
        let ownerUser = self.ownerUser
        let isGroupMessage = self.isGroup
        queue.async {
            var message = Message.createMessage(category: MessageCategory.SIGNAL_IMAGE.rawValue,
                                                conversationId: conversationId,
                                                userId: myUserId)
            message.mediaStatus = MediaStatus.PENDING.rawValue
            message.mediaUrl = image.fullsizedUrl.absoluteString
            message.mediaWidth = image.size.width
            message.mediaHeight = image.size.height
            if let thumbnail = thumbnail {
                message.thumbImage = thumbnail.base64Thumbnail()
            }
            message.mediaMimeType = "image/gif"
            SendMessageService.shared.sendMessage(message: message, ownerUser: ownerUser, isGroupMessage: isGroupMessage)
        }
    }
    
    func send(image: UIImage, quoteMessageId: String?) {
        let conversationId = self.conversationId
        let ownerUser = self.ownerUser
        let isGroupMessage = self.isGroup
        queue.async {
            var message = Message.createMessage(category: MessageCategory.SIGNAL_IMAGE.rawValue,
                                                conversationId: conversationId,
                                                userId: myUserId)
            let url = AttachmentContainer.url(for: .photos, filename: message.messageId + ExtensionName.jpeg.withDot)
            guard image.saveToFile(path: url) else {
                return
            }
            message.mediaStatus = MediaStatus.PENDING.rawValue
            message.mediaUrl = url.lastPathComponent
            message.mediaWidth = Int(image.size.width)
            message.mediaHeight = Int(image.size.height)
            message.quoteMessageId = quoteMessageId
            message.thumbImage = image.base64Thumbnail()
            message.mediaMimeType = "image/jpeg"
            SendMessageService.shared.sendMessage(message: message, ownerUser: ownerUser, isGroupMessage: isGroupMessage)
        }
    }
    
    func moveAndSendVideo(at source: URL, quoteMessageId: String?) {
        let conversationId = self.conversationId
        let ownerUser = self.ownerUser
        let isGroupMessage = self.isGroup
        queue.async {
            var message = Message.createMessage(category: MessageCategory.SIGNAL_VIDEO.rawValue,
                                                conversationId: conversationId,
                                                userId: myUserId)
            let url = AttachmentContainer.url(for: .videos, filename: message.messageId + "." + source.pathExtension)
            do {
                try FileManager.default.moveItem(at: source, to: url)
                let asset = AVAsset(url: url)
                guard asset.duration.isValid, let videoTrack = asset.tracks(withMediaType: .video).first else {
                    showAutoHiddenHud(style: .error, text: R.string.localizable.error_operation_failed())
                    return
                }
                if let thumbnail = UIImage(withFirstFrameOfVideoAtURL: url) {
                    let thumbnailURL = AttachmentContainer.videoThumbnailURL(videoFilename: url.lastPathComponent)
                    thumbnail.saveToFile(path: thumbnailURL)
                    message.thumbImage = thumbnail.base64Thumbnail()
                } else {
                    showAutoHiddenHud(style: .error, text: R.string.localizable.error_operation_failed())
                    return
                }
                message.mediaDuration = Int64(asset.duration.seconds * millisecondsPerSecond)
                let size = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
                message.mediaWidth = Int(abs(size.width))
                message.mediaHeight = Int(abs(size.height))
                message.mediaSize = FileManager.default.fileSize(url.path)
                message.mediaMimeType = FileManager.default.mimeType(ext: url.pathExtension)
                message.mediaUrl = url.lastPathComponent
                message.mediaStatus = MediaStatus.PENDING.rawValue
                message.quoteMessageId = quoteMessageId
                SendMessageService.shared.sendMessage(message: message, ownerUser: ownerUser, isGroupMessage: isGroupMessage)
            } catch {
                showAutoHiddenHud(style: .error, text: R.string.localizable.error_operation_failed())
            }
        }
    }
    
    func moveAndSendGifImage(at source: URL, image: UIImage, quoteMessageId: String?) {
        let conversationId = self.conversationId
        let ownerUser = self.ownerUser
        let isGroupMessage = self.isGroup
        queue.async {
            var message = Message.createMessage(category: MessageCategory.SIGNAL_IMAGE.rawValue,
                                                conversationId: conversationId,
                                                userId: myUserId)
            let filename = message.messageId + ".gif"
            let url = AttachmentContainer.url(for: .photos, filename: filename)
            do {
                try FileManager.default.moveItem(at: source, to: url)
                message.mediaStatus = MediaStatus.PENDING.rawValue
                message.mediaUrl = filename
                message.mediaWidth = Int(image.size.width * image.scale)
                message.mediaHeight = Int(image.size.height * image.scale)
                message.thumbImage = image.base64Thumbnail()
                message.mediaMimeType = "image/gif"
                SendMessageService.shared.sendMessage(message: message, ownerUser: ownerUser, isGroupMessage: isGroupMessage)
            } catch {
                showAutoHiddenHud(style: .error, text: R.string.localizable.error_operation_failed())
            }
        }
    }
    
    func send(asset: PHAsset, quoteMessageId: String?) {
        let conversationId = self.conversationId
        let ownerUser = self.ownerUser
        let isGroupMessage = self.isGroup
        let options = self.thumbnailRequestOptions
        queue.async {
            assert(asset.mediaType == .image || asset.mediaType == .video)
            let assetMediaTypeIsImage = asset.mediaType == .image
            let category: MessageCategory = assetMediaTypeIsImage ? .SIGNAL_IMAGE : .SIGNAL_VIDEO
            var message = Message.createMessage(category: category.rawValue,
                                                conversationId: conversationId,
                                                userId: myUserId)
            message.mediaStatus = MediaStatus.PENDING.rawValue
            message.mediaLocalIdentifier = asset.localIdentifier
            message.mediaWidth = asset.pixelWidth
            message.mediaHeight = asset.pixelHeight
            message.quoteMessageId = quoteMessageId
            if assetMediaTypeIsImage {
                message.mediaMimeType = asset.isGif ? "image/gif" : "image/jpeg"
            } else {
                message.mediaMimeType = "video/mp4"
            }
            let thumbnailSize = CGSize(width: 48, height: 48)
            PHImageManager.default().requestImage(for: asset, targetSize: thumbnailSize, contentMode: .aspectFit, options: options) { (image, info) in
                if let image = image {
                    message.thumbImage = image.base64Thumbnail()
                }
            }
            SendMessageService.shared.sendMessage(message: message, ownerUser: ownerUser, isGroupMessage: isGroupMessage)
        }
    }
    
}
