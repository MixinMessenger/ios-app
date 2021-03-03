import UIKit

class MusicInfoView: UIView, XibDesignable {
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        loadXib()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadXib()
    }
    
    func setImageViewBackground(isOpaque: Bool) {
        imageView.backgroundColor = isOpaque ? UIColor(displayP3RgbValue: 0xEFEFF4) : .clear
    }
    
}
