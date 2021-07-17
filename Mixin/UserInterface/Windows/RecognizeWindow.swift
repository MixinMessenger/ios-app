import UIKit

class RecognizeWindow: BottomSheetView {
    
    @IBOutlet weak var contentTextView: UITextView!
    @IBOutlet weak var copyButton: UIButton!
    @IBOutlet weak var actionButton: RoundedButton!
    @IBOutlet weak var actionButtonBottomConstraint: NSLayoutConstraint!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        contentTextView.delegate = self
    }
    
    func presentWindow(text: String) {
        contentTextView.text = text
        if textIsValidURL {
            actionButton.setTitle(R.string.localizable.action_open(), for: .normal)
            actionButtonBottomConstraint.constant = -12
            actionButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 38, bottom: 12, right: 38)
            copyButton.isHidden = false
        } else {
            actionButtonBottomConstraint.constant = copyButton.bounds.height
        }
        presentPopupControllerAnimated()
    }
    
    @IBAction func buttonAction(_ sender: Any) {
        if textIsValidURL {
            if let url = URL(string: contentTextView.text) {
                open(url)
            }
        } else {
            copyContent()
        }
    }
    
    @IBAction func copyAction(_ sender: Any) {
        copyContent()
    }
    
    @IBAction func dismissAction(_ sender: Any) {
        dismissPopupControllerAnimated()
    }
    
    class func instance() -> RecognizeWindow {
        return Bundle.main.loadNibNamed("RecognizeWindow", owner: nil, options: nil)?.first as! RecognizeWindow
    }
    
    private var textIsValidURL: Bool {
        let text = contentTextView.text!
        let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        if let match = detector.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
            return match.range.length == text.utf16.count
        } else {
            return false
        }
    }
    
    private func copyContent() {
        UIPasteboard.general.string = contentTextView.text
        dismissPopupControllerAnimated()
        showAutoHiddenHud(style: .notification, text: Localized.TOAST_COPIED)
    }
    
    @discardableResult private func open(_ url: URL) -> Bool {
        guard let container = UIApplication.homeContainerViewController else {
            return true
        }
        dismissPopupControllerAnimated()
        var parent = container.topMostChild
        if let visibleViewController = (parent as? UINavigationController)?.visibleViewController {
            parent = visibleViewController
        }
        MixinWebViewController.presentInstance(with: .init(conversationId: "", initialUrl: url), asChildOf: parent)
        return false
    }
    
}

extension RecognizeWindow: UITextViewDelegate {
    
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        return open(URL)
    }
    
}
