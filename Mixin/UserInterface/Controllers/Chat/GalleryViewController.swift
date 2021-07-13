import UIKit
import Photos
import AVKit
import MixinServices

protocol GalleryViewControllerDelegate: AnyObject {
    func galleryViewController(_ viewController: GalleryViewController, cellFor item: GalleryItem) -> GalleryTransitionSource?
    func galleryViewController(_ viewController: GalleryViewController, willShow item: GalleryItem)
    func galleryViewController(_ viewController: GalleryViewController, didShow item: GalleryItem)
    func galleryViewController(_ viewController: GalleryViewController, willDismiss item: GalleryItem)
    func galleryViewController(_ viewController: GalleryViewController, didDismiss item: GalleryItem, relativeOffset: CGFloat?)
    func galleryViewController(_ viewController: GalleryViewController, didCancelDismissalFor item: GalleryItem)
}

final class GalleryViewController: UIViewController, GalleryAnimatable {
    
    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var childForStatusBarStyle: UIViewController? {
        if let web = activeWebViewController {
            return web
        } else {
            return super.childForStatusBarStyle
        }
    }
    
    override var childForStatusBarHidden: UIViewController? {
        if let web = activeWebViewController {
            return web
        } else {
            return super.childForStatusBarHidden
        }
    }
    
    override var childForHomeIndicatorAutoHidden: UIViewController? {
        if let web = activeWebViewController {
            return web
        } else {
            return super.childForHomeIndicatorAutoHidden
        }
    }
    
    weak var delegate: GalleryViewControllerDelegate?
    
    var conversationId: String? {
        get {
            return modelController.conversationId
        }
        set {
            modelController.conversationId = newValue
        }
    }
    
    private let interPageSpacing: CGFloat = 20
    private let pageViewController: UIPageViewController
    private let modelController = GalleryItemModelController()
    private let backgroundView = UIView()
    
    private var transitionView: GalleryTransitionView?
    private var longPressRecognizer: UILongPressGestureRecognizer!
    private var itemToShowAfterAvPipStops: (GalleryItem, GalleryTransitionSource)?
    
    private(set) var panRecognizer: UIPanGestureRecognizer!
    
    private var activeWebViewController: WebViewController? {
        return parent?.children.compactMap({ $0 as? WebViewController })
            .filter({ !$0.isBeingDismissedAsChild })
            .last
    }
    
    var currentItemViewController: GalleryItemViewController? {
        return pageViewController.viewControllers?.first as? GalleryItemViewController
    }
    
    init() {
        let spacing = NSNumber(value: interPageSpacing.native)
        pageViewController = UIPageViewController(transitionStyle: .scroll,
                                                  navigationOrientation: .horizontal,
                                                  options: [.interPageSpacing: spacing])
        super.init(nibName: nil, bundle: nil)
        modelController.delegate = self
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func loadView() {
        view = GalleryView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        
        backgroundView.backgroundColor = .black
        view.addSubview(backgroundView)
        backgroundView.snp.makeEdgesEqualToSuperview()
        
        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.view.snp.makeEdgesEqualToSuperview()
        pageViewController.didMove(toParent: self)
        pageViewController.dataSource = modelController
        pageViewController.delegate = self
        if let scrollView = pageViewController.view.subviews.first(where: { $0 is UIScrollView }) {
            (view as? GalleryView)?.scrollView = scrollView as? UIScrollView
        }
        
        panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(panAction(_:)))
        panRecognizer.delegate = self
        view.addGestureRecognizer(panRecognizer)
        
        longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressAction(_:)))
        view.addGestureRecognizer(longPressRecognizer)
        NotificationCenter.default.addObserver(self, selector: #selector(willRecallMessage(_:)), name: SendMessageService.willRecallMessageNotification, object: nil)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        currentItemViewController?.isFocused = false
    }
    
    @objc func willRecallMessage(_ notification: Notification) {
        guard let messageId = notification.userInfo?[SendMessageService.UserInfoKey.messageId] as? String else {
            return
        }
        guard currentItemViewController?.item?.messageId == messageId else {
            return
        }
        dismiss(transitionViewInitialOffsetY: 0)
    }
    
    func show(item: GalleryItem, from source: GalleryTransitionSource) {
        show(items: [item], index: 0, from: source)
    }
    
    func show(items: [GalleryItem], index: Int, from source: GalleryTransitionSource) {
        itemToShowAfterAvPipStops = nil
        modelController.direction = source.direction
        let item = items[index]
        if let controller = UIApplication.homeContainerViewController?.pipController {
            if controller.item == item {
                controller.stopPipIfActive()
                return
            } else if item.category == .video || item.category == .live {
                if controller.isAvPipActive {
                    itemToShowAfterAvPipStops = (item, source)
                    controller.stopAvPipAndHandoverDelegate(to: self)
                    return
                } else {
                    controller.closeAction()
                }
            }
        }
        UIApplication.shared.keyWindow?.endEditing(true)
        backgroundView.alpha = 0
        pageViewController.view.alpha = 0
        delegate?.galleryViewController(self, willShow: item)
        
        if transitionView == nil || type(of: transitionView) != source.transitionViewType {
            transitionView = source.transitionViewType.init()
        }
        transitionView!.load(source: source)
        transitionView!.alpha = 1
        view.addSubview(transitionView!)
        transitionView!.transition(to: view)
        
        let viewController = modelController.dequeueReusableViewController(with: items, index: index)
        viewController.isFocused = true
        if let viewController = viewController as? GalleryImageItemViewController, case let .relativeOffset(offset) = source.imageWrapperView.position {
            viewController.scrollView.contentOffset.y = -offset * viewController.scrollView.contentSize.height
        }
        pageViewController.setViewControllers([viewController], direction: .forward, animated: false, completion: nil)
        
        animate(animations: {
            self.backgroundView.alpha = 1
        }, completion: {
            self.transitionView?.alpha = 0
            self.pageViewController.view.alpha = 1
            self.transitionView?.removeFromSuperview()
            self.delegate?.galleryViewController(self, didShow: item)
            if let vc = viewController as? GalleryVideoItemViewController {
                vc.hidePlayControlAfterPlaybackBegins = true
                vc.playAction(self)
            }
        })
    }
    
    func show(itemViewController viewController: GalleryItemViewController) {
        guard let item = viewController.item else {
            return
        }
        UIApplication.shared.keyWindow?.endEditing(true)
        var viewControllerToHide: GalleryItemViewController?
        if let homeContainer = UIApplication.homeContainerViewController, homeContainer.isShowingGallery {
            viewControllerToHide = currentItemViewController
        } else {
            delegate?.galleryViewController(self, willShow: item)
            backgroundView.alpha = 0
            pageViewController.view.alpha = 0
        }
        animate(animations: {
            viewControllerToHide?.view.alpha = 0
            self.backgroundView.alpha = 1
        }, completion: {
            self.delegate?.galleryViewController(self, didShow: item)
            self.pageViewController.setViewControllers([viewController], direction: .forward, animated: false, completion: nil)
            self.pageViewController.view.alpha = 1
            viewController.isFocused = true
            viewControllerToHide?.view.alpha = 1
        })
    }
    
    func dismiss(transitionViewInitialOffsetY: CGFloat, completion: (() -> Void)? = nil) {
        guard let itemViewController = currentItemViewController, let item = itemViewController.item else {
            return
        }
        delegate?.galleryViewController(self, willDismiss: item)
        pageViewController.view.alpha = 0
        pageViewController.view.transform = .identity
        
        if let transitionView = transitionView {
            view.addSubview(transitionView)
            transitionView.load(viewController: itemViewController)
            transitionView.center.y += transitionViewInitialOffsetY
            transitionView.alpha = 1
        }
        
        let relativeOffset: CGFloat?
        if item.shouldLayoutAsArticle, let offset = (itemViewController as? GalleryImageItemViewController)?.relativeOffset {
            relativeOffset = offset
        } else {
            relativeOffset = nil
        }
        if let source = delegate?.galleryViewController(self, cellFor: item) {
            transitionView?.transition(to: source)
        } else {
            animate(animations: {
                self.transitionView?.frame.origin.y = self.view.bounds.height
            })
        }
        currentItemViewController?.isFocused = false
        animate(animations: {
            self.backgroundView.alpha = 0
        }, completion: {
            self.delegate?.galleryViewController(self, didDismiss: item, relativeOffset: relativeOffset)
            self.pageViewController.view.alpha = 1
            self.transitionView?.alpha = 0
            completion?()
        })
    }
    
    func dismiss(pipController: GalleryVideoItemViewController) {
        guard let item = pipController.item, let container = UIApplication.homeContainerViewController else {
            return
        }
        pageViewController.setViewControllers([UIViewController()], direction: .forward, animated: false, completion: nil)
        
        container.addChild(pipController)
        container.view.addSubview(pipController.view)
        pipController.didMove(toParent: container)
        
        animate(animations: {
            self.backgroundView.alpha = 0
        }, completion: {
            self.delegate?.galleryViewController(self, didDismiss: item, relativeOffset: nil)
        })
    }
    
    func forward() {
        guard let id = currentItemViewController?.item?.messageId else {
            return
        }
        guard let message = MessageDAO.shared.getFullMessage(messageId: id) else {
            return
        }
        if message.category.hasSuffix("_LIVE"), let live = message.live, !(live.isShareable ?? true) {
            alert(R.string.localizable.chat_forward_invalid_live_not_shareable())
            return
        }
        let vc = MessageReceiverViewController.instance(content: .messages([message]))
        dismiss(transitionViewInitialOffsetY: 0) {
            UIApplication.homeNavigationController?.pushViewController(vc, animated: true)
        }
    }
    
    @objc func panAction(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: view)
        let progress = min(1, max(0, translation.y / (view.bounds.height / 3)))
        let item = currentItemViewController?.item
        switch recognizer.state {
        case .began:
            if let item = item {
                delegate?.galleryViewController(self, willDismiss: item)
            }
            currentItemViewController?.willBeginInteractiveDismissal()
            recognizer.setTranslation(.zero, in: view)
        case .changed:
            let y = max(0, translation.y)
            pageViewController.view.transform = CGAffineTransform(translationX: 0, y: y)
            backgroundView.alpha = max(0.4, 1 - progress)
        case .cancelled, .ended:
            if progress > 0.6 || recognizer.velocity(in: view).y > 800 {
                dismiss(transitionViewInitialOffsetY: translation.y)
            } else {
                currentItemViewController?.didCancelInteractiveDismissal()
                animate(animations: {
                    self.backgroundView.alpha = 1
                    self.pageViewController.view.transform = .identity
                }, completion: {
                    if let item = item {
                        self.delegate?.galleryViewController(self, didCancelDismissalFor: item)
                    }
                })
            }
        default:
            break
        }
    }
    
    @objc func longPressAction(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let itemViewController = currentItemViewController, !itemViewController.supportedActions.isEmpty else {
            return
        }
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        if itemViewController.supportedActions.contains(.forward) {
            alert.addAction(UIAlertAction(title: R.string.localizable.chat_message_menu_forward(), style: .default, handler: { (_) in
                self.forward()
            }))
        }
        if itemViewController.supportedActions.contains(.saveToLibrary) {
            alert.addAction(UIAlertAction(title: Localized.CHAT_PHOTO_SAVE, style: .default, handler: { (_) in
                PHPhotoLibrary.checkAuthorization { (authorized) in
                    if authorized {
                        itemViewController.saveToLibrary()
                    }
                }
            }))
        }
        if let url = (itemViewController as? GalleryImageItemViewController)?.detectedUrl {
            alert.addAction(UIAlertAction(title: Localized.SCAN_QR_CODE, style: .default, handler: { (_) in
                if !UrlWindow.checkUrl(url: url, clearNavigationStack: false) {
                    RecognizeWindow.instance().presentWindow(text: url.absoluteString)
                }
            }))
        }
        alert.addAction(UIAlertAction(title: Localized.DIALOG_BUTTON_CANCEL, style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
}

extension GalleryViewController: UIPageViewControllerDelegate {
    
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        let focus = pageViewController.viewControllers?.first as? GalleryItemViewController
        previousViewControllers.filter({
            $0 != focus
        }).forEach({
            ($0 as? GalleryItemViewController)?.isFocused = false
        })
        if let focus = focus {
            focus.isFocused = true
        }
    }
    
}

extension GalleryViewController: UIGestureRecognizerDelegate {
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return panRecognizer.velocity(in: view).y > 0
            && abs(panRecognizer.velocity(in: view).y) > abs(panRecognizer.velocity(in: view).x)
            && (currentItemViewController?.canPerformInteractiveDismissal ?? true)
    }
    
}

extension GalleryViewController: GalleryItemModelControllerDelegate {
    
    func modelController(_ controller: GalleryItemModelController, didLoadItemsBefore location: GalleryItem) {
        guard let current = currentItemViewController, location == current.item else {
            return
        }
        pageViewController.setViewControllers([current], direction: .forward, animated: false, completion: nil)
    }
    
    func modelController(_ controller: GalleryItemModelController, didLoadItemsAfter location: GalleryItem) {
        guard let current = currentItemViewController, location == current.item else {
            return
        }
        pageViewController.setViewControllers([current], direction: .forward, animated: false, completion: nil)
    }
    
}

extension GalleryViewController: AVPictureInPictureControllerDelegate {
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard let item = itemToShowAfterAvPipStops else {
            return
        }
        show(item: item.0, from: item.1)
    }
    
}
