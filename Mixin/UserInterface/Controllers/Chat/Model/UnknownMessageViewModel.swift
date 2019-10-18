import UIKit

class UnknownMessageViewModel: TextMessageViewModel {
    
    override var rawContent: String {
        return R.string.localizable.chat_unknown_category_hint()
            + R.string.localizable.chat_unknown_category_link()
    }
    
    override init(message: MessageItem, style: Style, fits layoutWidth: CGFloat) {
        super.init(message: message, style: style, fits: layoutWidth)
        statusImage = nil
    }
    
    override func linksMap(from attributedString: NSAttributedString) -> [NSRange : URL] {
        let location = (R.string.localizable.chat_unknown_category_hint() as NSString).length
        let length = (R.string.localizable.chat_unknown_category_link() as NSString).length
        let range = NSRange(location: location, length: length)
        return [range: .aboutUnknownMessageCategory]
    }
    
}
