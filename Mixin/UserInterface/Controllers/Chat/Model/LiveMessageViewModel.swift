import UIKit

class LiveMessageViewModel: PhotoRepresentableMessageViewModel {
    
    override class var bubbleImageSet: BubbleImageSet.Type {
        return LightRightBubbleImageSet.self
    }
    
    var badgeOrigin = CGPoint.zero
    
    private let badgeMargin = Margin(leading: 12, trailing: 4, top: 3, bottom: 0)
    
    override func layout(width: CGFloat, style: MessageViewModel.Style) {
        super.layout(width: width, style: style)
        if style.contains(.received) {
            badgeOrigin = CGPoint(x: contentFrame.origin.x + badgeMargin.leading,
                                  y: contentFrame.origin.y + badgeMargin.top)
        } else {
            badgeOrigin = CGPoint(x: contentFrame.origin.x + badgeMargin.trailing,
                                  y: contentFrame.origin.y + badgeMargin.top)
        }
    }
    
}
