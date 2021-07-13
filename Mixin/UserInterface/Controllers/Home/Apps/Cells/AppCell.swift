import UIKit

class AppCell: UICollectionViewCell {
    
    @IBOutlet weak var imageView: AvatarImageView?
    @IBOutlet weak var label: UILabel?
    @IBOutlet weak var imageContainerView: UIView!
    
    var item: AppItem? {
        didSet {
            updateUI()
        }
    }
    var snapshotView: HomeAppsSnapshotView {
        let iconView = imageContainerView.snapshotView(afterScreenUpdates: true)!
        iconView.frame = imageContainerView.frame
        guard let label = label else {
            return HomeAppsSnapshotView(frame: bounds, iconView: iconView)
        }
        let nameView = label.snapshotView(afterScreenUpdates: true)!
        nameView.frame = label.frame
        return HomeAppsSnapshotView(frame: bounds, iconView: iconView, nameView: nameView)
    }
    
    private var isShaking = false
    
    override func prepareForReuse() {
        super.prepareForReuse()
        imageView?.prepareForReuse()
        isShaking = false
        label?.isHidden = false
    }
    
    func updateUI() {
        guard let item = item as? AppModel, let app = item.app else {
            return
        }
        switch app {
        case .embedded(let embedded):
            label?.text = embedded.name
            imageView?.image = embedded.icon
        case .external(let user):
            label?.text = user.fullName
            imageView?.setImage(with: user)
        }
        label?.isHidden = false
    }
    
    func startShaking() {
        guard !isShaking else { return }
        isShaking = true
        let positionAnimation = CAKeyframeAnimation(keyPath: "position")
        positionAnimation.values = [CGPoint(x: -1, y: -1),
                                    CGPoint(x: 0, y: 0),
                                    CGPoint(x: -1, y: 0),
                                    CGPoint(x: 0, y: -1),
                                    CGPoint(x: -1, y: -1)]
        positionAnimation.calculationMode = .linear
        positionAnimation.isAdditive = true
        let transformAnimation = CAKeyframeAnimation(keyPath: "transform")
        transformAnimation.valueFunction = CAValueFunction(name: .rotateZ)
        transformAnimation.values = [-0.03525565, 0.03525565, -0.03525565]
        transformAnimation.calculationMode = .linear
        transformAnimation.isAdditive = true
        let animationGroup = CAAnimationGroup()
        animationGroup.duration = 0.25
        animationGroup.repeatCount = .infinity
        animationGroup.isRemovedOnCompletion = false
        animationGroup.beginTime = Double(arc4random() % 25) / 100.0
        animationGroup.animations = [positionAnimation, transformAnimation]
        animationGroup.isRemovedOnCompletion = false
        contentView.layer.add(animationGroup, forKey: "shakingAnimation")
    }
    
    func stopShaking() {
        isShaking = false
        contentView.layer.removeAllAnimations()
        contentView.transform = .identity
    }
    
}
