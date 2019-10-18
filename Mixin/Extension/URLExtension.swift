import Foundation

extension URL {
    
    static let blank = URL(string: "about:blank")!
    static let terms = URL(string: "https://mixin.one/pages/terms")!
    static let privacy = URL(string: "https://mixin.one/pages/privacy")!
    static let aboutEncryption = URL(string: "https://mixin.one/pages/1000007")!
    static let aboutUnknownMessageCategory = URL(string: "https://mixinmessenger.zendesk.com/hc/articles/360034949072")!
    static let emergencyContact = URL(string: "https://mixinmessenger.zendesk.com/hc/articles/360029154692")!
    
    func getKeyVals() -> Dictionary<String, String>? {
        var results = [String: String]()
        if let components = URLComponents(url: self, resolvingAgainstBaseURL: true), let queryItems = components.queryItems {
            for item in queryItems {
                results.updateValue(item.value ?? "", forKey: item.name)
            }
        }
        return results
    }

    func cloudExist() -> Bool {
        // Returns a Boolean indicating whether the item is targeted for storage in iCloud.
        return FileManager.default.isUbiquitousItem(at: self)
    }

    func cloudDownloaded() throws -> Bool {
        // A local copy of this item exists and is the most up-to-date version known to the device.
        return try resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus == .current
    }

    static func createTempUrl(fileExtension: String) -> URL {
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString.lowercased()).\(fileExtension)")
    }
}
