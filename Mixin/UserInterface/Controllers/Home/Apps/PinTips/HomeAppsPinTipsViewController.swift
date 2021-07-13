import UIKit

class HomeAppsPinTipsViewController: UIViewController {
    
    var topSpace: CGFloat = 0
    
    @IBOutlet weak var pinnedAppViewTopConstraint: NSLayoutConstraint!
    @IBOutlet weak var candidateAppLeadingConstraint: NSLayoutConstraint!
    @IBOutlet var pinnedAppSpaceConstraints: [NSLayoutConstraint]!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let mode = HomeAppsMode.regular
        candidateAppLeadingConstraint.constant = mode.sectionInset.left + mode.itemSize.width + mode.minimumInteritemSpacing + 10
        pinnedAppSpaceConstraints.forEach({ $0.constant = HomeAppsMode.pinned.minimumInteritemSpacing })
        pinnedAppViewTopConstraint.constant = topSpace
    }
    
    @IBAction func dismiss(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }
    
}
