import UIKit
import MixinServices
import AlignedCollectionViewFlowLayout

final class HomeAppsViewController: ResizablePopupViewController {
    
    @IBOutlet weak var noPinnedHintLabel: UILabel!
    @IBOutlet weak var pinnedCollectionView: UICollectionView!
    @IBOutlet weak var pinnedCollectionLayout: UICollectionViewFlowLayout!
    @IBOutlet weak var candidateCollectionView: UICollectionView!
    @IBOutlet weak var candidateCollectionLayout: UICollectionViewFlowLayout!
    @IBOutlet weak var pageControl: UIPageControl!

    @IBOutlet weak var titleBarHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var pinnedCollectionViewLeadingConstraint: NSLayoutConstraint!
    @IBOutlet weak var pinnedCollectionViewTrailingConstraint: NSLayoutConstraint!
    @IBOutlet weak var pinnedWrapperHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var candidateCollectionViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var pageControlBottomConstraint: NSLayoutConstraint!
    
    override var resizableScrollView: UIScrollView? {
        candidateCollectionView
    }
    
    private let cellCountPerRow = 4
    private let cellSize = CGSize(width: 80, height: 100)
    private let cellCountPerPage = (row: 4, column: ScreenHeight.current == .medium ? 3 : 4)
    
    private lazy var resizeGestureCoordinator = HomeAppResizeGestureCoordinator(scrollView: candidateCollectionView)
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
    
    private var pinnedAppModelController: PinnedHomeAppsModelController!
    private var candidateAppModelController: CandidateHomeAppsModelController!
    private var candidateEmptyHintLabelIfLoaded: UILabel?
    
    class func instance() -> HomeAppsViewController {
        R.storyboard.home.apps()!
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        updatePreferredContentSizeHeight(size: size)
        view.addGestureRecognizer(resizeRecognizer)
        resizeRecognizer.delegate = resizeGestureCoordinator
        
        pinnedAppModelController = PinnedHomeAppsModelController(collectionView: pinnedCollectionView)
        pinnedCollectionView.dataSource = pinnedAppModelController
        pinnedCollectionView.delegate = self
        pinnedCollectionView.dragInteractionEnabled = true
        pinnedCollectionView.dragDelegate = pinnedAppModelController
        pinnedCollectionView.dropDelegate = pinnedAppModelController
        pinnedAppModelController.reloadData(completion: { [weak self] apps in
            self?.noPinnedHintLabel.isHidden = !apps.isEmpty
        })
        
        candidateAppModelController = CandidateHomeAppsModelController(collectionView: candidateCollectionView)
        candidateCollectionView.dataSource = candidateAppModelController
        candidateCollectionView.delegate = self
        candidateCollectionView.dragInteractionEnabled = true
        candidateCollectionView.dragDelegate = candidateAppModelController
        candidateCollectionView.addInteraction(candidateAppModelController.dropInteraction)
        candidateAppModelController.reloadData(completion: { [weak self] (apps) in
            self?.setCandidateEmptyHintHidden(!apps.isEmpty)
        })
        
        let window = AppDelegate.current.mainWindow
        let maxHeight = window.bounds.height - window.safeAreaInsets.top
        let candidateHeight = maxHeight - titleBarHeightConstraint.constant - pinnedWrapperHeightConstraint.constant
        candidateCollectionViewHeightConstraint.constant = candidateHeight
        
        NotificationCenter.default.addObserver(self, selector: #selector(updateNoPinnedHint), name: AppGroupUserDefaults.User.homeAppIdsDidChangeNotification, object: nil)
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        let cellCount = CGFloat(cellCountPerRow)
        let iconInset: CGFloat = 36
        
        let candidateInset = round((view.bounds.width - 2 * cellCount * iconInset - cellCount * pinnedCollectionLayout.itemSize.width) / (2 - 2 * cellCount))
        candidateCollectionLayout.sectionInset.left = candidateInset
        candidateCollectionLayout.sectionInset.right = candidateInset
        let candidateCellsWidth = view.bounds.width
            - candidateCollectionLayout.sectionInset.horizontal
            - candidateCollectionLayout.minimumInteritemSpacing * CGFloat(cellCountPerRow - 1)
        let candidateCellWidth = floor(candidateCellsWidth / CGFloat(cellCountPerRow))
        candidateCollectionLayout.itemSize.width = candidateCellWidth
        
        let inset = candidateCollectionLayout.sectionInset.left
            - pinnedCollectionViewLeadingConstraint.constant
            + (candidateCollectionLayout.itemSize.width - pinnedCollectionLayout.itemSize.width) / 2
        pinnedCollectionLayout.sectionInset.left = inset
        pinnedCollectionLayout.sectionInset.right = inset
        let pinnedSpacing: CGFloat = {
            let cellsWidth = pinnedCollectionLayout.itemSize.width * CGFloat(cellCountPerRow)
            let totalSpacing = view.bounds.width
                - pinnedCollectionViewLeadingConstraint.constant
                - pinnedCollectionViewTrailingConstraint.constant
                - pinnedCollectionLayout.sectionInset.horizontal
                - cellsWidth
            return floor(totalSpacing / CGFloat(cellCountPerRow))
        }()
        pinnedCollectionLayout.minimumInteritemSpacing = pinnedSpacing
    }
    
    override func preferredContentHeight(forSize size: Size) -> CGFloat {
        view.layoutIfNeeded()
        return titleBarHeightConstraint.constant
            + pinnedWrapperHeightConstraint.constant
            + cellSize.height * CGFloat(cellCountPerPage.column)
            + pageControlBottomConstraint.constant
            + AppDelegate.current.mainWindow.safeAreaInsets.bottom
            + 30
    }
    
    @IBAction func pageControlValueChanged(_ sender: UIPageControl) {
        
    }
    
    @IBAction func dismissAction(_ sender: Any) {
        dismissAsChild(completion: nil)
    }
    
    @objc func updateNoPinnedHint() {
        noPinnedHintLabel.isHidden = !AppGroupUserDefaults.User.homeAppIds.isEmpty
    }
    
    func setCandidateEmptyHintHidden(_ hidden: Bool) {
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

    override func updatePreferredContentSizeHeight(size: ResizablePopupViewController.Size) {
        guard !isBeingDismissed else {
            return
        }
        let height = preferredContentHeight(forSize: size)
        preferredContentSize.height = height
        view.frame.origin.y = backgroundButton.bounds.height - height
    }
    
}

extension HomeAppsViewController: UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        let app: HomeApp
        if collectionView == pinnedCollectionView {
            app = pinnedAppModelController.apps[indexPath.row]
        } else if collectionView == candidateCollectionView {
            app = candidateAppModelController.apps[indexPath.row]
        } else {
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

}

extension HomeAppsViewController {

    @objc func backgroundTappingAction() {
        dismissAsChild(completion: nil)
    }

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
        UIView.animate(withDuration: 0.3, animations: {
            self.view.frame.origin.y = self.backgroundButton.bounds.height - self.preferredContentSize.height
            self.backgroundButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        })
    }

}
