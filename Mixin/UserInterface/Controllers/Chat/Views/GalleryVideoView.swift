import UIKit
import AVFoundation
import MixinServices

final class GalleryVideoView: UIView, GalleryAnimatable {
    
    let contentView = UIView()
    let coverImageView = UIImageView()
    let player = AVPlayer()
    let playerView = PlayerView()
    let controlView = R.nib.galleryVideoControlView(owner: nil)!
    
    var coverSize = CGSize(width: 1, height: 1)
    var videoRatio: CGFloat = 1
    var isPipMode = false {
        didSet {
            if isPipMode {
                controlView.style.insert(.pip)
            } else {
                controlView.style.remove(.pip)
            }
            layoutIfNeeded()
        }
    }
    
    private var playerStatusObserver: NSKeyValueObservation?
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        prepare()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        prepare()
    }
    
    convenience init() {
        self.init(frame: CGRect(x: 0, y: 0, width: 375, height: 240))
        backgroundColor = .clear
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let contentHeight = min(bounds.height, ceil(bounds.width / videoRatio))
        contentView.bounds.size = CGSize(width: bounds.width , height: contentHeight)
        contentView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        
        playerView.frame = contentView.bounds
        coverImageView.frame = coverSize.rect(fittingSize: contentView.bounds.size)
        
        layoutControlView()
    }
    
    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        layoutControlView()
    }
    
    private func layoutControlView() {
        let safeAreaInsets = AppDelegate.current.mainWindow.safeAreaInsets
        if isPipMode || safeAreaInsets.top <= 20 {
            controlView.frame = bounds
        } else {
            controlView.frame = bounds.inset(by: safeAreaInsets)
        }
    }
    
    private func prepare() {
        contentView.frame = bounds
        contentView.clipsToBounds = true
        contentView.backgroundColor = .black
        
        coverImageView.contentMode = .scaleAspectFill
        
        playerView.backgroundColor = .clear
        playerView.layer.videoGravity = .resizeAspect
        playerView.layer.player = player
        playerStatusObserver = player.observe(\.status) { player, _ in
            if player.status == .failed {
                if let error = player.error {
                    Logger.write(error: error)
                } else {
                    Logger.write(log: "[GalleryVideoView] Player reports failed but no error is provided")
                }
            }
        }
        
        contentView.addSubview(coverImageView)
        contentView.addSubview(playerView)
        addSubview(contentView)
        
        controlView.frame = bounds
        addSubview(controlView)
    }
    
}
