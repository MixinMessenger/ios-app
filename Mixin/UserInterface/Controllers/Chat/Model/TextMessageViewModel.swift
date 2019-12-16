import UIKit

class TextMessageViewModel: DetailInfoMessageViewModel {
    
    private enum Font {
        private static let font = UIFont.systemFont(ofSize: 16)
        static let ctFont = CTFontCreateWithFontDescriptor(font.fontDescriptor as CTFontDescriptor, 0, nil)
        static let lineHeight = round(font.lineHeight)
    }
    
    class var ctFont: CTFont {
        return Font.ctFont
    }
    
    class var lineHeight: CGFloat {
        return Font.lineHeight
    }
    
    class var textColor: UIColor {
        return .black
    }
    
    var content: CoreTextLabel.Content?
    var contentLabelFrame = CGRect.zero
    var highlightPaths = [UIBezierPath]()
    var textSize = CGSize.zero
    
    private let timeLeftMargin: CGFloat = 20
    private let minimumTextSize = CGSize(width: 5, height: 18)
    private let linkColor = UIColor.systemTint
    private let hightlightPathCornerRadius: CGFloat = 4
    
    private var contentSize = CGSize.zero // contentSize is textSize concatenated with additionalTrailingSize and fullname width
    
    override var debugDescription: String {
        return super.debugDescription + ", textSize: \(textSize), contentSize: \(contentSize), contentLength: \(message.content.count)"
    }
    
    var fullnameHeight: CGFloat {
        return style.contains(.fullname) ? fullnameFrame.height : 0
    }

    var backgroundWidth: CGFloat {
        return contentAdditionalLeadingMargin + contentSize.width + contentMargin.horizontal
    }
    
    var contentLabelTopMargin: CGFloat {
        return style.contains(.fullname) ? fullnameHeight : contentMargin.top
    }
    
    var contentAdditionalLeadingMargin: CGFloat {
        return 0
    }
    
    var rawContent: String {
        return message.content
    }
    
    var timeStatusSize: CGSize {
        let statusImageWidth = showStatusImage
            ? ImageSet.MessageStatus.size.width
            : 0
        let width = timeLeftMargin
            + timeSize.width
            + statusImageWidth
            + DetailInfoMessageViewModel.statusLeftMargin
        return CGSize(width: width, height: 16)
    }
    
    override init(message: MessageItem, style: Style, fits layoutWidth: CGFloat) {
        super.init(message: message, style: style, fits: layoutWidth)
        let str = NSMutableAttributedString(string: rawContent)
        let cfStr = str as CFMutableAttributedString
        // Detect links
        let linksMap = self.linksMap(from: str)
        // Set attributes
        setDefaultAttributes(on: cfStr)
        for link in linksMap {
            let range = CFRange(nsRange: link.key)
            CFAttributedStringSetAttribute(cfStr, range, kCTForegroundColorAttributeName, linkColor)
        }
        // Make CTLine and Origins
        let (lines, lineOrigins, lineRanges, lastLineWidth) = typeset(attributedString: cfStr)
        if textSize.height < minimumTextSize.height {
            textSize = minimumTextSize
        }
        // Make Links
        var links = [Link]()
        for link in linksMap {
            let linkRects: [CGRect] = lines.enumerated().compactMap({ (index, line) -> CGRect? in
                let lineOrigin = lineOrigins[index]
                let lineRange = NSRange(cfRange: lineRanges[index])
                if let intersection = lineRange.intersection(link.key) {
                    return line.frame(forRange: intersection, lineOrigin: lineOrigin)
                } else {
                    return nil
                }
            })
            var path: UIBezierPath?
            for linkRect in linkRects {
                let newPath = UIBezierPath(roundedRect: linkRect, cornerRadius: hightlightPathCornerRadius)
                if path != nil {
                    path!.append(newPath)
                } else {
                    path = newPath
                }
            }
            if let path = path {
                links += linkRects.map{ Link(hitFrame: $0, backgroundPath: path, url: link.value) }
            }
        }
        // Make content
        self.content = CoreTextLabel.Content(lines: lines, lineOrigins: lineOrigins, links: links)
        // Calculate content size
        let additionalTrailingSize = timeStatusSize
        var contentSize = textSize
        let lastLineWithTrailingWidth = lastLineWidth + additionalTrailingSize.width
        if lastLineWithTrailingWidth > maxContentWidth {
            contentSize.height += additionalTrailingSize.height
        } else if lines.count == 1 {
            contentSize.width = lastLineWithTrailingWidth
        } else {
            contentSize.width = max(contentSize.width, lastLineWithTrailingWidth)
        }
        if style.contains(.fullname) {
            if message.userIsBot {
                let identityIconWidth = DetailInfoMessageViewModel.identityIconLeftMargin + DetailInfoMessageViewModel.identityIconSize.width
                contentSize.width = min(maxContentWidth, max(contentSize.width, fullnameWidth + identityIconWidth))
            } else {
                contentSize.width = min(maxContentWidth, max(contentSize.width, fullnameWidth))
            }
        }
        self.contentSize = contentSize
        layout()
    }
    
    override func layout() {
        if style.contains(.received) {
            backgroundImageFrame = CGRect(x: MessageViewModel.backgroundImageMargin.leading,
                                          y: 0,
                                          width: backgroundWidth,
                                          height: contentSize.height + contentLabelTopMargin + contentMargin.bottom)
            contentLabelFrame = CGRect(x: ceil(backgroundImageFrame.origin.x + contentMargin.leading),
                                       y: contentLabelTopMargin,
                                       width: textSize.width,
                                       height: textSize.height)
        } else {
            backgroundImageFrame = CGRect(x: layoutWidth - MessageViewModel.backgroundImageMargin.leading - backgroundWidth,
                                          y: 0,
                                          width: backgroundWidth,
                                          height: contentSize.height + contentLabelTopMargin + contentMargin.bottom)
            contentLabelFrame = CGRect(x: ceil(backgroundImageFrame.origin.x + contentMargin.trailing),
                                       y: contentLabelTopMargin,
                                       width: textSize.width,
                                       height: textSize.height)
        }
        cellHeight = backgroundImageFrame.height + bottomSeparatorHeight
        super.layout()
    }
    
    func highlight(keyword: String) {
        guard let content = content else {
            return
        }
        let messageContent = message.content as NSString
        var searchRange = NSRange(location: 0, length: messageContent.length)
        var highlightRanges = [NSRange]()
        while searchRange.location < messageContent.length {
            let foundRange = messageContent.range(of: keyword, options: .caseInsensitive, range: searchRange)
            if foundRange.location != NSNotFound {
                highlightRanges.append(foundRange)
                searchRange.location = foundRange.location + foundRange.length
                searchRange.length = messageContent.length - searchRange.location
            } else {
                break
            }
        }
        assert(content.lines.count == content.lineOrigins.count)
        for (i, line) in content.lines.enumerated() {
            let lineOrigin = content.lineOrigins[i]
            for highlightRange in highlightRanges {
                guard let highlightRect = line.frame(forRange: highlightRange, lineOrigin: lineOrigin) else {
                    continue
                }
                let path = UIBezierPath(roundedRect: highlightRect, cornerRadius: hightlightPathCornerRadius)
                highlightPaths.append(path)
            }
        }
    }
    
    func removeHighlights() {
        highlightPaths = []
    }
    
    func linksMap(from attributedString: NSAttributedString) -> [NSRange: URL] {
        var map = [NSRange: URL]()
        Link.detector.enumerateMatches(in: attributedString, options: [], using: { (result, _, _) in
            guard let result = result, let url = result.url else {
                return
            }
            map[result.range] = url
        })
        return map
    }
    
    func setDefaultAttributes(on string: CFMutableAttributedString) {
        let fullRange = CFRange(location: 0, length: CFAttributedStringGetLength(string))
        CFAttributedStringSetAttribute(string, fullRange, kCTFontAttributeName, type(of: self).ctFont)
        CFAttributedStringSetAttribute(string, fullRange, kCTForegroundColorAttributeName, type(of: self).textColor)
    }
    
    typealias TypesetResult = (lines: [CTLine], lineOrigins: [CGPoint], lineRanges: [CFRange], lastLineWidth: CGFloat)
    func typeset(attributedString: CFAttributedString) -> TypesetResult {
        let typesetter = CTTypesetterCreateWithAttributedString(attributedString)
        
        var lines = [CTLine]()
        var lineOrigins = [CGPoint]()
        var lineRanges = [CFRange]()
        var characterIndex: CFIndex = 0
        var y: CGFloat = 4
        var lastLineWidth: CGFloat = 0
        
        while true {
            let lineCharacterCount = CTTypesetterSuggestLineBreak(typesetter, characterIndex, Double(maxContentWidth))
            if lineCharacterCount > 0 {
                let lineRange = CFRange(location: characterIndex, length: lineCharacterCount)
                let line = CTTypesetterCreateLine(typesetter, lineRange)
                let lineWidth = ceil(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line)))
                let lineOrigin = CGPoint(x: 0, y: y)
                lines.append(line)
                lineOrigins.append(lineOrigin)
                lineRanges.append(lineRange)
                textSize.height += type(of: self).lineHeight
                textSize.width = max(textSize.width, lineWidth)
                y += type(of: self).lineHeight
                lastLineWidth = lineWidth
                characterIndex += lineCharacterCount
            } else {
                break
            }
        }
        
        return (lines, lineOrigins.reversed(), lineRanges, lastLineWidth)
    }
    
}
