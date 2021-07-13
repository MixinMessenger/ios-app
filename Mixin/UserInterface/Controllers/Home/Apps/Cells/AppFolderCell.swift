import UIKit

class AppFolderCell: AppCell {
    
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var wrapperView: UIView!
    
    var currentPage: Int {
        guard collectionView.frame.size.width != 0 else {
            return 0
        }
        return Int(collectionView.contentOffset.x) / Int(collectionView.frame.size.width)
    }
    
    private var placeholderView: UIView?
    private var apps: [[AppModel]] = [] {
        didSet {
            collectionView.reloadData()
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        wrapperView.isHidden = false
    }
    
    override var snapshotView: HomeAppsSnapshotView {
        let snapshotView = super.snapshotView
        let wrapperView = wrapperView.snapshotView(afterScreenUpdates: true)!
        wrapperView.frame = snapshotView.iconView.frame
        snapshotView.insertSubview(wrapperView, belowSubview: snapshotView.iconView)
        return snapshotView
    }
    
    override func updateUI() {
        super.updateUI()
        guard let folder = item as? AppFolderModel else { return }
        apps = folder.pages
        label?.text = folder.name
        placeholderView?.removeFromSuperview()
        imageContainerView.transform = .identity
        collectionView.reloadData()
    }
    
    func leaveEditingMode() {
        guard let folder = item as? AppFolderModel, let lastPageApps = apps.last, lastPageApps.count == 0 else {
            return
        }
        apps.removeLast()
        folder.pages = apps
        collectionView.reloadData()
    }
    
}

extension AppFolderCell {
    
    func moveToFirstAvailablePage(animated: Bool = true) {
        if let folder = item as? AppFolderModel, (apps.last?.count ?? 0) > 0 {
            folder.pages.append([])
            apps.append([])
        }
        let appsPerPage = HomeAppsMode.nestedFolder.appsPerPage
        for (page, appsInPage) in apps.enumerated() {
            if appsInPage.count < appsPerPage {
                if page != currentPage {
                    move(to: page, animated: animated)
                }
                break
            }
        }
    }
    
    func move(to page: Int, animated: Bool) {
        guard page < apps.count else { return }
        let indexPath = IndexPath(item: page, section: 0)
        collectionView.scrollToItem(at: indexPath, at: .left, animated: animated)
    }
    
    func move(view: UIView, toCellPositionAtIndex index: Int, completion: (() -> Void)? = nil) {
        guard let currentPageCell = collectionView.cellForItem(at: IndexPath(item: currentPage, section: 0)) as? AppPageCell,
              let flowLayout = currentPageCell.collectionView.collectionViewLayout as? UICollectionViewFlowLayout,
              let layoutAttributes = flowLayout.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else {
            return
        }
        if layoutAttributes.frame.minX == 0 {
            layoutAttributes.frame.origin.x = flowLayout.sectionInset.left
        }
        let convertedRect1 = convert(layoutAttributes.frame, from: currentPageCell)
        let convertedRect2 = convert(convertedRect1, to: view.superview!)
        UIView.animate(withDuration: 0.35, animations: {
            view.frame = convertedRect2
        }, completion: { _ in
            completion?()
        })
    }
    
    func revokeFolderCreation(completion: @escaping () -> Void) {
        guard let currentPageCell = collectionView.cellForItem(at: IndexPath(item: currentPage, section: 0)) as? AppPageCell,
              let appCell = currentPageCell.collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? AppCell else {
            return
        }
        let convertedRect1 = currentPageCell.convert(appCell.imageView?.frame ?? .zero, from: appCell)
        let convertedRect2 = convert(convertedRect1, from: currentPageCell)
        let imageView = UIImageView(frame: convertedRect2)
        imageView.image = appCell.imageView?.image
        contentView.addSubview(imageView)
        appCell.imageView?.isHidden = true
        UIView.animate(withDuration: 0.55, animations: {
            imageView.transform = .transform(rect: imageView.frame, to: self.imageContainerView.frame)
            self.imageContainerView.transform = CGAffineTransform.identity.scaledBy(x: 0.01, y: 0.01)
            self.label?.alpha = 0
        }, completion: { _ in
            self.placeholderView = imageView
            appCell.imageView?.isHidden = false
            completion()
        })
    }
    
}

extension AppFolderCell: UICollectionViewDataSource, UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return apps.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard indexPath.item < apps.count else {
            return UICollectionViewCell()
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: R.reuseIdentifier.app_page, for: indexPath)!
        cell.mode = .nestedFolder
        cell.draggedItem = nil
        cell.items = apps[indexPath.item]
        cell.collectionView.reloadData()
        return cell
    }
    
}
