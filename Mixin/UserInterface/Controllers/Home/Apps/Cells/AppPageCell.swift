import UIKit

protocol AppPageCellDelegate: AnyObject {
    
    func didSelect(cell: AppCell, on pageCell: AppPageCell)
    
}

class AppPageCell: UICollectionViewCell {
    
    weak var delegate: AppPageCellDelegate?
    
    @IBOutlet weak var collectionView: UICollectionView!
    
    var mode: HomeAppsMode = .regular {
        didSet {
            updateLayout()
        }
    }
    var items: [AppItem] = []
    var draggedItem: AppItem?
    
    private var isEditing = false
    
    func enterEditingMode() {
        guard !isEditing else { return }
        isEditing = true
        for cell in collectionView.visibleCells {
            guard let cell = cell as? AppCell else { return }
            cell.startShaking()
            if let cell = cell as? AppFolderCell {
                cell.moveToFirstAvailablePage()
            }
        }
    }
    
    func leaveEditingMode() {
        guard isEditing else { return }
        isEditing = false
        for cell in collectionView.visibleCells {
            guard let cell = cell as? AppCell else { return }
            cell.stopShaking()
            if let cell = cell as? AppFolderCell {
                cell.leaveEditingMode()
                cell.move(to: 0, animated: true)
            }
        }
    }
    
    func delete(item: AppItem) {
        guard let index = items.firstIndex(where: { $0 === item }),
              let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) else {
            return
        }
        UIView.animate(withDuration: 0.25, animations: {
            cell.contentView.transform = CGAffineTransform.identity.scaledBy(x: 0.0001, y: 0.0001)
        }, completion: { _ in
            self.items.remove(at: index)
            self.collectionView.performBatchUpdates({
                self.collectionView.deleteItems(at: [IndexPath(item: index, section: 0)])
            }, completion: { _ in
                cell.contentView.transform = .identity
            })
        })
    }
    
    func updateSectionInset(animated: Bool = true) {
        guard mode == .pinned, let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
            return
        }
        let newHorizontalSectionInset: CGFloat
        let interitemSpacing = mode.minimumInteritemSpacing
        if items.count < mode.appsPerRow {
            let count = CGFloat(items.count)
            let totalSpace = (flowLayout.itemSize.width * count) + (interitemSpacing * (count - 1))
            newHorizontalSectionInset = (frame.size.width - totalSpace) / 2
        } else {
            newHorizontalSectionInset = mode.sectionInset.left
        }
        if animated {
            collectionView.performBatchUpdates({
                flowLayout.sectionInset = UIEdgeInsets(top: mode.sectionInset.top, left: newHorizontalSectionInset, bottom: mode.sectionInset.bottom, right: newHorizontalSectionInset)
            }, completion: nil)
        } else {
            flowLayout.sectionInset = UIEdgeInsets(top: mode.sectionInset.top, left: newHorizontalSectionInset, bottom: mode.sectionInset.bottom, right: newHorizontalSectionInset)
        }
    }
    
    private func updateLayout() {
        guard let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
            return
        }
        flowLayout.itemSize = mode.itemSize
        flowLayout.minimumInteritemSpacing = mode.minimumInteritemSpacing
        flowLayout.minimumLineSpacing = mode.minimumLineSpacing
        flowLayout.sectionInset = mode.sectionInset
        updateSectionInset(animated: false)
    }
    
}

extension AppPageCell: UICollectionViewDelegate, UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard indexPath.item < items.count else {
            return UICollectionViewCell(frame: .zero)
        }
        if let folder = items[indexPath.item] as? AppFolderModel {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: R.reuseIdentifier.app_folder, for: indexPath)!
            cell.item = folder
            if isEditing {
                cell.startShaking()
                cell.moveToFirstAvailablePage(animated: false)
            } else {
                cell.stopShaking()
                cell.leaveEditingMode()
            }
            if let draggedItem = draggedItem, draggedItem === folder {
                cell.contentView.isHidden = true
            } else {
                cell.contentView.isHidden = false
            }
            return cell
        } else if let app = items[indexPath.item] as? AppModel {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: R.reuseIdentifier.app, for: indexPath)!
            cell.item = app
            if isEditing {
                cell.startShaking()
            } else {
                cell.stopShaking()
            }
            if let draggedItem = draggedItem, draggedItem === app {
                cell.contentView.isHidden = true
            } else {
                cell.contentView.isHidden = false
            }
            cell.label?.isHidden = mode == .pinned
            return cell
        }
        return UICollectionViewCell(frame: .zero)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath) as? AppCell else {
            return
        }
        delegate?.didSelect(cell: cell, on: self)
    }
    
}
