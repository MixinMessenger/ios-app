import UIKit
import MixinServices

final class HomeAppsViewController: UIViewController {
    
    @IBOutlet weak var noPinnedHintLabel: UILabel!
    @IBOutlet weak var pinnedCollectionView: UICollectionView!
    @IBOutlet weak var candidateCollectionView: UICollectionView!
    @IBOutlet weak var candidateCollectionLayout: UICollectionViewFlowLayout!
    @IBOutlet weak var pageControl: UIPageControl!
    
    @IBOutlet weak var titleBarHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var pinnedWrapperHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var candidateCollectionViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var pageControlTopConstraint: NSLayoutConstraint!
    
    private lazy var candidateEmptyHintLabel: UILabel = {
        let label = UILabel()
        label.text = R.string.localizable.home_apps_candidate_empty()
        label.backgroundColor = .background
        label.textColor = .accessoryText
        label.numberOfLines = 0
        label.textAlignment = .center
        label.setFont(scaledFor: .systemFont(ofSize: 14), adjustForContentSize: true)
        candidateEmptyHintLabelIfLoaded = label
        return label
    }()
    private lazy var backgroundButton: UIButton = {
        let button = UIButton()
        button.backgroundColor = UIColor.black.withAlphaComponent(0)
        button.addTarget(self, action: #selector(backgroundTappingAction), for: .touchUpInside)
        return button
    }()
    private var candidateEmptyHintLabelIfLoaded: UILabel?
    
    private var appsManager: HomeAppsManager!
    private var appsItemManager: HomeAppsItemManager!
    
    class func instance() -> HomeAppsViewController {
        R.storyboard.home.apps()!
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        appsItemManager = HomeAppsItemManager()
        noPinnedHintLabel.isHidden = !appsItemManager.pinnedItems.isEmpty
        setCandidateEmptyHintHidden(!appsItemManager.candidateItems.isEmpty)
        appsManager = HomeAppsManager(viewController: self,
                                      candidateCollectionView: candidateCollectionView,
                                      items: appsItemManager.candidateItems,
                                      pinnedCollectionView: pinnedCollectionView,
                                      pinnedItems: appsItemManager.pinnedItems)
        appsManager.delegate = self
        pageControl.numberOfPages = appsManager.items.count
        pageControl.currentPage = 0
        candidateCollectionViewHeightConstraint.constant = HomeAppsMode.regular.itemSize.height * CGFloat(HomeAppsMode.regular.rowsPerPage)
        updatePreferredContentSizeHeight()
        NotificationCenter.default.addObserver(self, selector: #selector(updateNoPinnedHint), name: AppGroupUserDefaults.User.homeAppIdsDidChangeNotification, object: nil)
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory else {
            return
        }
        DispatchQueue.main.async {
            self.updatePreferredContentSizeHeight()
        }
    }
    
    @IBAction func pageControlValueChanged(_ sender: UIPageControl) {
        let x = CGFloat(pageControl.currentPage) * candidateCollectionView.frame.width
        let offset = CGPoint(x: x, y: 0)
        candidateCollectionView.setContentOffset(offset, animated: true)
    }
    
    @IBAction func dismissAction(_ sender: Any) {
        dismiss()
    }
    
}

extension HomeAppsViewController: UIScrollViewDelegate {
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let page = scrollView.contentOffset.x / scrollView.frame.size.width
        pageControl.currentPage = Int(round(page))
    }
    
}

extension HomeAppsViewController {
    
    func dismissAsChild(completion: (() -> Void)?) {
        UIView.animate(withDuration: 0.3, animations: {
            self.view.frame.origin.y = self.backgroundButton.bounds.height
            self.backgroundButton.backgroundColor = UIColor.black.withAlphaComponent(0)
        }) { (finished) in
            self.willMove(toParent: nil)
            self.view.removeFromSuperview()
            self.removeFromParent()
            self.backgroundButton.removeFromSuperview()
            completion?()
        }
    }
    
    func presentAsChild(of parent: UIViewController) {
        loadViewIfNeeded()
        backgroundButton.frame = parent.view.bounds
        backgroundButton.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        parent.addChild(self)
        parent.view.addSubview(backgroundButton)
        didMove(toParent: parent)
        
        view.frame = CGRect(x: 0,
                            y: backgroundButton.bounds.height,
                            width: backgroundButton.bounds.width,
                            height: backgroundButton.bounds.height)
        view.autoresizingMask = .flexibleTopMargin
        backgroundButton.addSubview(view)
        UIView.animate(withDuration: 0.3) {
            self.view.frame.origin.y = self.backgroundButton.bounds.height - self.preferredContentSize.height
            self.backgroundButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        } completion: { _ in
            self.showPinTipsIfNeeded()
        }
        
    }
    
    @objc private func backgroundTappingAction() {
        dismiss()
    }
    
    private func dismiss() {
        if appsManager.isEditing {
            appsManager.leaveEditingMode()
        } else {
            dismissAsChild(completion: nil)
        }
    }
    
    @objc private func updateNoPinnedHint() {
        noPinnedHintLabel.isHidden = !appsManager.pinnedItems.isEmpty
    }
    
    private func updatePreferredContentSizeHeight() {
        guard !isBeingDismissed else {
            return
        }
        let height = preferredContentHeight()
        preferredContentSize.height = height
        view.frame.origin.y = backgroundButton.bounds.height - height
    }
    
    private func preferredContentHeight() -> CGFloat {
        view.layoutIfNeeded()
        return titleBarHeightConstraint.constant
            + pinnedWrapperHeightConstraint.constant
            + candidateCollectionViewHeightConstraint.constant
            + pageControlTopConstraint.constant
            + ceil(pageControl.bounds.height)
            + AppDelegate.current.mainWindow.safeAreaInsets.bottom
            + 22
    }
    
    private func setCandidateEmptyHintHidden(_ hidden: Bool) {
        if hidden {
            candidateEmptyHintLabelIfLoaded?.removeFromSuperview()
        } else {
            let x = candidateCollectionLayout.sectionInset.left
            let y = candidateCollectionLayout.itemSize.height
            let width = candidateCollectionView.bounds.width
                - candidateCollectionLayout.sectionInset.horizontal
            let height = preferredContentSize.height
                - titleBarHeightConstraint.constant
                - pinnedWrapperHeightConstraint.constant
                - candidateCollectionLayout.itemSize.height
            candidateEmptyHintLabel.frame = CGRect(x: x, y: y, width: width, height: round(height / 3 * 2))
            if candidateEmptyHintLabel.superview == nil {
                candidateCollectionView.addSubview(candidateEmptyHintLabel)
            }
        }
    }
    
    private func showPinTipsIfNeeded() {
        guard !AppGroupUserDefaults.User.homeAppsPinTips else { return }
        AppGroupUserDefaults.User.homeAppsPinTips = true
        let viewController = HomeAppsPinTipsViewController()
        viewController.topSpace = view.frame.origin.y + 80.0
        viewController.modalPresentationStyle = .overFullScreen
        viewController.modalTransitionStyle = .crossDissolve
        present(viewController, animated: true, completion: nil)
    }
    
}

extension HomeAppsViewController: HomeAppsManagerDelegate {
    
    func homeAppsManager(_ manager: HomeAppsManager, didSelectApp app: AppModel) {
        guard let app = app.app else {
            return
        }
        switch app {
        case let .embedded(app):
            dismissAsChild(completion: app.action)
        case let .external(user):
            let item = UserItem.createUser(from: user)
            let vc = UserProfileViewController(user: item)
            present(vc, animated: true, completion: nil)
        }
    }
    
    func homeAppsManager(_ manager: HomeAppsManager, didMoveToPage page: Int) {
        pageControl.currentPage = page
    }
    
    func homeAppsManager(_ manager: HomeAppsManager, didUpdatePageCount pageCount: Int) {
        pageControl.numberOfPages = pageCount
    }
    
    func homeAppsManagerDidUpdateItems(_ manager: HomeAppsManager) {
        appsItemManager.updateItems(manager.pinnedItems, manager.items)
        setCandidateEmptyHintHidden(!manager.items.isEmpty)
        updateNoPinnedHint()
    }
    
    func homeAppsManagerDidEnterEditingMode(_ manager: HomeAppsManager) {}
    
    func homeAppsManagerDidLeaveEditingMode(_ manager: HomeAppsManager) {}
    
    func homeAppsManager(_ manager: HomeAppsManager, didBeginFolderDragOutWithTransfer transfer: HomeAppsDragInteractionTransfer) {}
    
}
