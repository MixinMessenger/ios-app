import UIKit

class HomeAppsSnapshotView: UIView {
    
    var iconView: UIView
    var nameView: UIView?
    
    required init(frame: CGRect, iconView: UIView, nameView: UIView? = nil) {
        self.iconView = iconView
        self.nameView = nameView
        super.init(frame: frame)
        addSubview(iconView)
        if let nameView = nameView {
            addSubview(nameView)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
