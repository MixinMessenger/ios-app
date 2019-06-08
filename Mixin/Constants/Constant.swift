import Foundation
import UIKit

extension NSNotification.Name {

    static let SocketStatusChanged = NSNotification.Name("one.mixin.ios.websocket.status.changed")

    static let ConversationDidChange = NSNotification.Name("one.mixin.ios.sqlite.messages.changed")

    static let AccountDidChange = NSNotification.Name("one.mixin.ios.account.changed")

    static let ContactsDidChange = NSNotification.Name("one.mixin.ios.contacts.changed")

    static let UserDidChange = NSNotification.Name("one.mixin.ios.user.changed")

    static let ParticipantDidChange = NSNotification.Name("one.mixin.ios.participant.changed")

    static let AssetsDidChange = NSNotification.Name("one.mixin.ios.assets.changed")

    static let AssetVisibleDidChange = NSNotification.Name("one.mixin.ios.asset.visible.changed")

    static let SnapshotDidChange = NSNotification.Name("one.mixin.ios.snapshot.changed")

    static let AddressDidChange = NSNotification.Name("one.mixin.ios.addresses.changed")

    static let DefaultAddressDidChange = NSNotification.Name("one.mixin.ios.addresses.default.changed")

    static let FavoriteStickersDidChange = NSNotification.Name("one.mixin.ios.favorite.stickers.changed")
    
    static let StickerUsedAtDidUpdate = NSNotification.Name("one.mixin.ios.sticker.usedat.changed")
    
    static let StorageUsageDidChange = NSNotification.Name("one.mixin.ios.storage.changed")
    
    static let HiddenAssetsDidChange = NSNotification.Name("one.mixin.ios.hidden.assets.changed")

    static let BackupDidChange = NSNotification.Name("one.mixin.ios.backup.changed")

    static let UserSessionDidChange = NSNotification.Name("one.mixin.ios.session.changed")
}

enum NotificationActionIdentifier {
    static let reply = "reply"
    static let mute = "mute" // preserved
}

enum NotificationCategoryIdentifier {
    static let message = "message"
    static let call = "call"
}

enum NotificationRequestIdentifier {
    static let showInApp = "show_in_app"
    static let call = "call"
}

struct ConversationChange {
    
    let conversationId: String
    let action: Action
    
    enum Action {
        case reload
        case update(conversation: ConversationItem)
        case updateConversation(conversation: ConversationResponse)
        case addMessage(message: MessageItem)
        case updateGroupIcon(iconUrl: String)
        case updateMessage(messageId: String)
        case updateMessageStatus(messageId: String, newStatus: MessageStatus)
        case updateMediaStatus(messageId: String, mediaStatus: MediaStatus)
        case updateUploadProgress(messageId: String, progress: Double)
        case updateDownloadProgress(messageId: String, progress: Double)
        case startedUpdateConversation
        case recallMessage(messageId: String)
    }
    
}

struct SuiteName {
    static var crypto = "one.mixin.ios.crypto"
    static var common = "one.mixin.ios.common"
    static var database = "one.mixin.ios.database"
    static var wallet = "one.mixin.ios.wallet"
    static let call = "one.mixin.ios.call"
}

struct Storyboard {
    static let home = UIStoryboard(name: "Home", bundle: Bundle.main)
    static let login = UIStoryboard(name: "Login", bundle: Bundle.main)
    static let chat = UIStoryboard(name: "Chat", bundle: Bundle.main)
    static let contact = UIStoryboard(name: "Contact", bundle: Bundle.main)
    static let camera = UIStoryboard(name: "Camera", bundle: Bundle.main)
    static let common = UIStoryboard(name: "Common", bundle: Bundle.main)
    static let group = UIStoryboard(name: "Group", bundle: Bundle.main)
    static let wallet = UIStoryboard(name: "Wallet", bundle: Bundle.main)
    static let setting = UIStoryboard(name: "Setting", bundle: Bundle.main)
    static let photo = UIStoryboard(name: "Photo", bundle: Bundle.main)
}

struct MixinFile {
    
    enum ChatDirectory: String {
        case photos = "Photos"
        case files = "Files"
        case videos = "Videos"
        case audios = "Audios"
        
        var messageCategorySuffix: String {
            switch self {
            case .photos:
                return "_IMAGE"
            case .files:
                return "_DATA"
            case .videos:
                return "_VIDEO"
            case .audios:
                return "_AUDIO"
            }
        }

        static func getDirectory(category: String) -> ChatDirectory? {
            if category.hasSuffix("_IMAGE") {
                return .photos
            } else if category.hasSuffix("_DATA") {
                return .files
            } else if category.hasSuffix("_AUDIO") {
                return .audios
            } else if category.hasSuffix("_VIDEO") {
                return .videos
            } else {
                return nil
            }
        }
    }

    static var iCloudBackupDirectory: URL? {
        return FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent(AccountAPI.shared.accountIdentityNumber).appendingPathComponent("Backup")
    }

    static var rootDirectory: URL {
        let dir = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent(AccountAPI.shared.accountIdentityNumber)
        _ = FileManager.default.createNobackupDirectory(dir)
        return dir
    }

    static var logPath: URL {
        let url = rootDirectory.appendingPathComponent("Log")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
        return url
    }

    static var databaseURL: URL {
        return rootDirectory.appendingPathComponent("mixin.db")
    }

    static var signalDatabasePath: String {
        let dir = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        return dir.appendingPathComponent("signal.db").path
    }

    static var backupDatabase: URL {
        return rootDirectory.appendingPathComponent("mixin.backup.db")
    }

    static func url(ofChatDirectory directory: ChatDirectory, filename: String?) -> URL {
        let url = rootDirectory.appendingPathComponent("Chat").appendingPathComponent(directory.rawValue)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
        if let filename = filename {
            return url.appendingPathComponent(filename)
        } else {
            return url
        }
    }

    static func url(ofChatDirectory directory: ChatDirectory, messageId: String, mimeType: String) -> URL {
        let url = rootDirectory.appendingPathComponent("Chat").appendingPathComponent(directory.rawValue)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
        let fileExtension = FileManager.default.pathExtension(mimeType: mimeType).lowercased()
        return url.appendingPathComponent("\(messageId).\(fileExtension)")
    }
    
    static func clean(chatDirectory: ChatDirectory) {
        let resourcePath = url(ofChatDirectory: chatDirectory, filename: nil).path
        guard let onDiskFilenames = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) else {
            return
        }
        if chatDirectory == .videos {
            let referencedFilenames = MessageDAO.shared
                .getMediaUrls(likeCategory: chatDirectory.messageCategorySuffix)
                .map({ NSString(string: $0).deletingPathExtension })
            for onDiskFilename in onDiskFilenames where !referencedFilenames.contains(where: { onDiskFilename.contains($0) }) {
                let path = MixinFile.url(ofChatDirectory: .videos, filename: onDiskFilename)
                try? FileManager.default.removeItem(at: path)
            }
        } else {
            let referencedFilenames = Set(MessageDAO.shared.getMediaUrls(likeCategory: chatDirectory.messageCategorySuffix))
            for onDiskFilename in onDiskFilenames where !referencedFilenames.contains(onDiskFilename) {
                let path = MixinFile.url(ofChatDirectory: chatDirectory, filename: onDiskFilename)
                try? FileManager.default.removeItem(at: path)
            }
        }
    }
    
    static func cleanAllChatDirectories() {
        let dirs: [ChatDirectory] = [.photos, .audios, .files, .videos]
        dirs.forEach(clean)
    }
    
    static var groupIconsUrl: URL {
        let url = rootDirectory.appendingPathComponent("Group").appendingPathComponent("Icons")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
        return url
    }

}

let muteDuration8H: Int64 = 8 * 60 * 60
let muteDuration1Week: Int64 = 7 * 24 * 60 * 60
let muteDuration1Year: Int64 = 365 * 24 * 60 * 60

enum ExtensionName: String {
    
    case jpeg = "jpg"
    case mp4
    case html
    case ogg
    case gif
    
    var withDot: String {
        return "." + rawValue
    }
    
}

enum StatusBarHeight {
    static let normal: CGFloat = 20
    static let inCall: CGFloat = 40
}

let currentDecimalSeparator = Locale.current.decimalSeparator ?? "."

let iTunesAppUrlRegex = try? NSRegularExpression(pattern: "^https://itunes\\.apple\\.com/.*app.*id[0-9]", options: .caseInsensitive)
