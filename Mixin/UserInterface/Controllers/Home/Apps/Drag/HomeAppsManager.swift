import UIKit
import MixinServices

protocol HomeAppsManagerDelegate: AnyObject {
    
    func homeAppsManagerDidUpdateItems(_ manager: HomeAppsManager)
    func homeAppsManagerDidEnterEditingMode(_ manager: HomeAppsManager)
    func homeAppsManagerDidLeaveEditingMode(_ manager: HomeAppsManager)
    func homeAppsManager(_ manager: HomeAppsManager, didSelectApp app: AppModel)
    func homeAppsManager(_ manager: HomeAppsManager, didMoveToPage page: Int)
    func homeAppsManager(_ manager: HomeAppsManager, didUpdatePageCount pageCount: Int)
    func homeAppsManager(_ manager: HomeAppsManager, didBeginFolderDragOutWithTransfer transfer: HomeAppsDragInteractionTransfer)
    
}

class HomeAppsManager: NSObject {
    
    weak var delegate: HomeAppsManagerDelegate?
    
    unowned var viewController: UIViewController
    unowned var candidateCollectionView: UICollectionView
    unowned var pinnedCollectionView: UICollectionView?
    
    var items: [[AppItem]] {
        didSet {
            delegate?.homeAppsManager(self, didUpdatePageCount: items.count)
            delegate?.homeAppsManagerDidUpdateItems(self)
        }
    }
    var pinnedItems: [AppItem] {
        didSet {
            delegate?.homeAppsManagerDidUpdateItems(self)
        }
    }
    var isEditing = false
    var isInAppsFolderViewController: Bool { pinnedCollectionView == nil }
    var currentPage: Int {
        guard candidateCollectionView.frame.size.width != 0 else {
            return 0
        }
        return Int(candidateCollectionView.contentOffset.x) / Int(candidateCollectionView.frame.size.width)
    }
    var currentPageCell: AppPageCell? {
        let visibleCells = candidateCollectionView.visibleCells
        if visibleCells.count == 0 {
            return candidateCollectionView.subviews.first as? AppPageCell
        } else {
            return visibleCells.first as? AppPageCell
        }
    }
    
    var currentDragInteraction: HomeAppsDragInteraction?
    var currentFolderInteraction: HomeAppsFolderInteraction?
    var openFolderInfo: HomeAppsOpenFolderInfo?
    
    var pageTimer: Timer?
    var folderTimer: Timer?
    var folderRemovalTimer: Timer?
    
    var ignoreDragOutOnTop = false
    var ignoreDragOutOnBottom = false
    
    var longPressRecognizer = UILongPressGestureRecognizer()
    let tapRecognizer = UITapGestureRecognizer()
    let feedback = UIImpactFeedbackGenerator()
    
    init(viewController: UIViewController, candidateCollectionView: UICollectionView, items: [[AppItem]], pinnedCollectionView: UICollectionView? = nil, pinnedItems:[AppItem] = []) {
        self.viewController = viewController
        self.candidateCollectionView = candidateCollectionView
        self.pinnedCollectionView = pinnedCollectionView
        self.items = items
        self.pinnedItems = pinnedItems
        
        super.init()
        
        if let flowLayout = candidateCollectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            flowLayout.itemSize = pinnedCollectionView != nil ? HomeAppsMode.regular.pageSize : HomeAppsMode.folder.pageSize
        }
        if let flowLayout = pinnedCollectionView?.collectionViewLayout as? UICollectionViewFlowLayout {
            flowLayout.itemSize = HomeAppsMode.pinned.pageSize
        }
        self.candidateCollectionView.dataSource = self
        self.candidateCollectionView.delegate = self
        self.pinnedCollectionView?.dataSource = self
        self.pinnedCollectionView?.delegate = self
        longPressRecognizer.addTarget(self, action: #selector(handleLongPressGesture(_:)))
        self.viewController.view.addGestureRecognizer(longPressRecognizer)
        tapRecognizer.isEnabled = false
        tapRecognizer.delegate = self
        tapRecognizer.cancelsTouchesInView = false
        tapRecognizer.addTarget(self, action: #selector(handleTapGesture(gestureRecognizer:)))
        self.viewController.view.addGestureRecognizer(tapRecognizer)
        NotificationCenter.default.addObserver(self, selector: #selector(leaveEditingMode), name: UIApplication.willResignActiveNotification, object: nil)
    }
    
}

extension HomeAppsManager {
    
    @objc func handleTapGesture(gestureRecognizer: UITapGestureRecognizer) {
        guard isEditing else { return }
        var touchPoint = gestureRecognizer.location(in: viewController.view)
        guard let (collectionView, pageCell) = viewInfos(at: touchPoint) else {
            return
        }
        touchPoint = gestureRecognizer.location(in: collectionView)
        touchPoint.x -= collectionView.contentOffset.x
        if pageCell.collectionView.indexPathForItem(at: touchPoint) == nil {
            leaveEditingMode()
        }
    }
    
    func viewInfos(at point: CGPoint) -> (collectionView: UICollectionView, cell: AppPageCell)? {
        let collectionView: UICollectionView
        if let pinnedCollectionView = pinnedCollectionView, pinnedCollectionView.frame.contains(viewController.view.convert(point, to: pinnedCollectionView)) {
            collectionView = pinnedCollectionView
        } else {
            collectionView = candidateCollectionView
        }
        let convertedPoint = viewController.view.convert(point, to: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: convertedPoint), let cell = collectionView.cellForItem(at: indexPath) as? AppPageCell {
            return (collectionView, cell)
        } else if let cell = collectionView.visibleCells.first as? AppPageCell {
            return (collectionView, cell)
        } else {
            return nil
        }
    }
    
    func enterEditingMode(occurHaptic: Bool = true) {
        guard !isEditing else { return }
        isEditing = true
        if occurHaptic {
            feedback.impactOccurred()
        }
        for cell in candidateCollectionView.visibleCells + (pinnedCollectionView?.visibleCells ?? []) {
            if let cell = cell as? AppPageCell {
                cell.enterEditingMode()
            }
        }
        // add an empty page
        if items[items.count - 1].count > 0 {
            items.append([])
            candidateCollectionView.insertItems(at: [IndexPath(item: items.count - 1, section: 0)])
        }
        tapRecognizer.isEnabled = true
        delegate?.homeAppsManagerDidEnterEditingMode(self)
    }
    
    @objc func leaveEditingMode() {
        guard isEditing else { return }
        isEditing = false
        for cell in candidateCollectionView.visibleCells + (pinnedCollectionView?.visibleCells ?? []) {
            if let cell = cell as? AppPageCell {
                cell.leaveEditingMode()
            }
        }
        // remove empty page
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let emptyIndex = self.items.enumerated().compactMap( { $1.count == 0 ? $0 : nil })
            self.items.remove(at: emptyIndex)
            self.candidateCollectionView.deleteItems(at: emptyIndex.map({ IndexPath(item: $0, section: 0) }))
        }
        tapRecognizer.isEnabled = false
        delegate?.homeAppsManagerDidLeaveEditingMode(self)
    }
    
    // update items for current page after end drag
    func updateState(forPageCell pageCell: AppPageCell) {
        var updateItems: [AppItem] = []
        for i in 0..<pageCell.collectionView.visibleCells.count {
            let indexPath = IndexPath(item: i, section: 0)
            if let cell = pageCell.collectionView.cellForItem(at: indexPath) as? AppCell, let item = cell.item {
                updateItems.append(item)
            }
        }
        if let pinnedCollectionView = pinnedCollectionView, pinnedCollectionView.visibleCells.contains(pageCell) {
            pinnedItems = updateItems
        } else {
            guard let pageIndexPath = candidateCollectionView.indexPath(for: pageCell) else {
                return
            }
            items[pageIndexPath.row] = updateItems
        }
        pageCell.items = updateItems
    }
    
    // moves last item in page to next and rearranges next pages if needed
    func moveLastItem(inPage page: Int) {
        var currentPageItems = items[page + 1]
        currentPageItems.insert(items[page].removeLast(), at: 0)
        items[page + 1] = currentPageItems
        let appsPerPage = isInAppsFolderViewController ? HomeAppsMode.folder.appsPerPage : HomeAppsMode.regular.appsPerPage
        if currentPageItems.count >  appsPerPage {
            moveLastItem(inPage: page + 1)
        }
    }
    
    func perform(transfer: HomeAppsDragInteractionTransfer, showPlaceholder: Bool = false) {
        viewController.view.removeGestureRecognizer(longPressRecognizer)
        longPressRecognizer = transfer.gestureRecognizer
        longPressRecognizer.removeTarget(nil, action: nil)
        longPressRecognizer.addTarget(self, action: #selector(handleLongPressGesture(_:)))
        viewController.view.addGestureRecognizer(longPressRecognizer)
        currentDragInteraction = transfer.interaction.copy()
        currentDragInteraction?.needsUpdate = true
        if showPlaceholder {
            let placeholderView = transfer.interaction.placeholderView
            placeholderView.center = viewController.view.convert(placeholderView.center, from: placeholderView.superview)
            viewController.view.addSubview(placeholderView)
        }
    }
    
}

extension HomeAppsManager: UICollectionViewDataSource, UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView == candidateCollectionView {
            return items.count
        } else {
            return 1
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let items = collectionView == candidateCollectionView ? items[indexPath.row] : pinnedItems
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: R.reuseIdentifier.app_page, for: indexPath)!
        cell.items = items
        cell.draggedItem = currentDragInteraction?.item
        cell.delegate = self
        cell.collectionView.reloadData()
        if isInAppsFolderViewController {
            cell.mode = .folder
        } else {
            cell.mode = collectionView == candidateCollectionView ? .regular : .pinned
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? AppPageCell else {
            return
        }
        if let currentInteraction = currentDragInteraction, currentInteraction.needsUpdate {
            cell.items = items[indexPath.row]
            currentInteraction.currentPageCell = cell
            currentInteraction.currentIndexPath = IndexPath(item: cell.collectionView(cell.collectionView, numberOfItemsInSection: 0) - 1, section: 0)
            currentInteraction.needsUpdate = false
        }
        cell.draggedItem = currentDragInteraction?.item
        cell.collectionView.reloadData()
        if isEditing {
            cell.enterEditingMode()
        } else {
            cell.leaveEditingMode()
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? AppPageCell, isEditing else {
            return
        }
        cell.leaveEditingMode()
    }
    
}

extension HomeAppsManager: UIScrollViewDelegate {
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let page = scrollView.contentOffset.x / scrollView.frame.width
        delegate?.homeAppsManager(self, didMoveToPage: Int(roundf(Float(page))))
    }
    
}

extension HomeAppsManager: AppPageCellDelegate {
    
    func didSelect(cell: AppCell, on pageCell: AppPageCell) {
        if let cell = cell as? AppFolderCell {
            showFolder(from: cell)
        } else if let item = cell.item as? AppModel, !isEditing {
            delegate?.homeAppsManager(self, didSelectApp: item)
        }
    }
    
}

extension HomeAppsManager: UIGestureRecognizerDelegate {
    // disable tag when clear button tapped in folder controller
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.view is UIButton {
            return false
        }
        return true
    }
    
}
