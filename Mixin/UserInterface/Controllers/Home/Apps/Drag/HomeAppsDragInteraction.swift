import UIKit

class HomeAppsDragInteraction {
    
    let item: AppItem
    let originalPageCell: AppPageCell
    let originalIndexPath: IndexPath
    var currentPageCell: AppPageCell
    var currentIndexPath: IndexPath
    let placeholderView: HomeAppsSnapshotView
    let dragOffset: CGSize
    var needsUpdate = false
    var savedState: [[AppItem]]?
    
    required init(placeholderView: HomeAppsSnapshotView, dragOffset: CGSize, item: AppItem, originalPageCell: AppPageCell, originalIndexPath: IndexPath) {
        self.placeholderView = placeholderView
        self.dragOffset = dragOffset
        self.item = item
        self.originalPageCell = originalPageCell
        self.originalIndexPath = originalIndexPath
        currentPageCell = originalPageCell
        currentIndexPath = originalIndexPath
    }
    
    func movePlaceholderView(to point: CGPoint) {
        var offsettedTouchPoint = point
        offsettedTouchPoint.x += dragOffset.width
        offsettedTouchPoint.y += dragOffset.height
        placeholderView.center = offsettedTouchPoint
    }
    
    func copy() -> HomeAppsDragInteraction {
        let interaction = HomeAppsDragInteraction(placeholderView: placeholderView, dragOffset: dragOffset, item: item, originalPageCell: originalPageCell, originalIndexPath: originalIndexPath)
        interaction.currentPageCell = currentPageCell
        interaction.currentIndexPath = currentIndexPath
        return interaction
    }
    
    func transitionToFolderWrapperView() {
        UIView.animate(withDuration: 0.2) {
            self.placeholderView.nameView?.alpha = 0
        }
    }
    
    func transitionFromFolderWrapperView() {
        UIView.animate(withDuration: 0.2) {
            self.placeholderView.nameView?.alpha = 1
        }
    }
}

struct HomeAppsDragInteractionTransfer {
    var gestureRecognizer: UILongPressGestureRecognizer
    var interaction: HomeAppsDragInteraction
}
