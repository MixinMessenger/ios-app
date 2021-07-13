import Foundation

public struct TransferLiveData: Codable {
    
    public let width: Int
    public let height: Int
    public let thumbUrl: String
    public let url: String
    public let isShareable: Bool?
    
    enum CodingKeys: String, CodingKey {
        case width
        case height
        case thumbUrl = "thumb_url"
        case url
        case isShareable = "shareable"
    }
    
    public init(width: Int, height: Int, thumbUrl: String, url: String, shareable: Bool) {
        self.width = width
        self.height = height
        self.thumbUrl = thumbUrl
        self.url = url
        self.isShareable = shareable
    }
    
}
