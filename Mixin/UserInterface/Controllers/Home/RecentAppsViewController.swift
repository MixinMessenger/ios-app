import UIKit
import MixinServices

class RecentAppsViewController: UIViewController {
    
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var collectionLayout: UICollectionViewFlowLayout!
    
    @IBOutlet weak var collectionViewHeightConstraint: NSLayoutConstraint!
    
    private let cellCountPerRow = 4
    private let maxRowCount = 2
    private let cellMinWidth: CGFloat = 60
    private let queue = OperationQueue()
    
    private var users = [UserItem]()
    private var needsReload = true
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        queue.maxConcurrentOperationCount = 1
        scrollView.delegate = self
        collectionView.dataSource = self
        collectionView.delegate = self
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didChangeRecentlyUsedAppIds),
                                               name: AppGroupUserDefaults.User.didChangeRecentlyUsedAppIdsNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(userDidChange(_:)),
                                               name: UserDAO.userDidChangeNotification,
                                               object: nil)
        reloadIfNeeded()
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let cellsWidth = cellMinWidth * CGFloat(cellCountPerRow)
        let totalSpacing = view.bounds.width - cellsWidth
        let spacing = floor(totalSpacing / CGFloat(cellCountPerRow + 1))
        collectionLayout.itemSize = CGSize(width: cellMinWidth + spacing, height: 109)
        collectionLayout.sectionInset = UIEdgeInsets(top: 0, left: spacing / 2, bottom: 0, right: spacing / 2)
    }
    
    @IBAction func hideSearchAction() {
        let top = UIApplication.homeNavigationController?.topViewController
        (top as? HomeViewController)?.hideSearch()
    }
    
    @objc func didChangeRecentlyUsedAppIds() {
        needsReload = true
    }
    
    @objc func userDidChange(_ notification: Notification) {
        guard let userId = (notification.userInfo?[UserDAO.UserInfoKey.user] as? UserItem)?.userId else {
            return
        }
        if users.contains(where: { $0.userId == userId }) {
            needsReload = true
        }
    }
    
    func reloadIfNeeded() {
        guard needsReload else {
            return
        }
        needsReload = false
        queue.cancelAllOperations()
        let maxIdCount = maxRowCount * cellCountPerRow
        let op = BlockOperation()
        op.addExecutionBlock { [unowned op, weak self] in
            guard self != nil, !op.isCancelled, LoginManager.shared.isLoggedIn else {
                return
            }
            let ids = AppGroupUserDefaults.User.recentlyUsedAppIds.prefix(maxIdCount)
            let users = UserDAO.shared.getUsers(ofAppIds: Array(ids))
            DispatchQueue.main.sync {
                guard let weakSelf = self, !op.isCancelled else {
                    return
                }
                weakSelf.reload(users: users)
            }
        }
        queue.addOperation(op)
    }
    
    private func reload(users: [UserItem]) {
        self.users = users
        contentView.isHidden = users.isEmpty
        if !users.isEmpty {
            let lineCount = users.count > cellCountPerRow ? 2 : 1
            let height = collectionLayout.itemSize.height * CGFloat(lineCount)
            collectionViewHeightConstraint.constant = height
            collectionView.reloadData()
            view.layoutIfNeeded()
        }
    }
    
}

extension RecentAppsViewController: UIGestureRecognizerDelegate {
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let location = gestureRecognizer.location(in: scrollView)
        return !contentView.frame.contains(location)
    }
    
}

extension RecentAppsViewController: UIScrollViewDelegate {
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView == self.scrollView else {
            return
        }
        if scrollView.panGestureRecognizer.velocity(in: scrollView).y < 0 {
            hideSearchAction()
        }
    }
    
}

extension RecentAppsViewController: UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return users.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: R.reuseIdentifier.recent_app, for: indexPath)!
        cell.imageView?.setImage(with: users[indexPath.row])
        cell.label?.text = users[indexPath.row].fullName
        return cell
    }
    
}

extension RecentAppsViewController: UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let parent = parent as? SearchViewController else {
            return
        }
        let user = users[indexPath.row]
        let vc = ConversationViewController.instance(ownerUser: user)
        parent.searchTextField.resignFirstResponder()
        parent.homeNavigationController?.pushViewController(vc, animated: true)
        vc.transitionCoordinator?.animate(alongsideTransition: nil, completion: { (_) in
            parent.homeViewController?.hideSearch()
        })
    }
    
}
