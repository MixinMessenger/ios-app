import UIKit

protocol ConversationKeyboardManagerDelegate: class {
    func conversationKeyboardManager(_ manager: ConversationKeyboardManager, keyboardWillChangeFrameTo newFrame: CGRect, intent: ConversationKeyboardManager.KeyboardIntent)
}

class ConversationKeyboardManager {
    
    static let minReasonableKeyboardHeight: CGFloat = 270
    static var lastKeyboardHeight: CGFloat = minReasonableKeyboardHeight
    
    let inputAccessoryView: FrameObservingInputAccessoryView
    
    private(set) var isShowingKeyboard = false
    
    weak var delegate: ConversationKeyboardManagerDelegate?
    
    private var justChangedInputAccessoryViewHeight = false
    
    var inputAccessoryViewHeight: CGFloat {
        get {
            return inputAccessoryView.frame.height
        }
        set {
            guard let heightConstraint = inputAccessoryView.constraints.filter({ ($0.firstItem as? UIView) == inputAccessoryView && $0.firstAttribute == .height }).first, heightConstraint.constant != newValue else {
                return
            }
            justChangedInputAccessoryViewHeight = true
            heightConstraint.constant = newValue
            inputAccessoryView.window?.rootViewController?.view.layoutIfNeeded()
        }
    }
    
    init() {
        inputAccessoryView = FrameObservingInputAccessoryView(height: 0)
        inputAccessoryView.manager = self
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)), name: .UIKeyboardWillChangeFrame, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func keyboardWillChangeFrame(_ notification: Notification) {
        guard let endFrame = (notification.userInfo?[UIKeyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
            return
        }
        ConversationKeyboardManager.lastKeyboardHeight = max(ConversationKeyboardManager.minReasonableKeyboardHeight,
                                                             endFrame.height - inputAccessoryView.frame.height)
        if keyboardFrameIsInvisible(endFrame) && isShowingKeyboard {
            isShowingKeyboard = false
            delegate?.conversationKeyboardManager(self, keyboardWillChangeFrameTo: endFrame, intent: .hide)
        } else if !keyboardFrameIsInvisible(endFrame) && !isShowingKeyboard {
            isShowingKeyboard = true
            delegate?.conversationKeyboardManager(self, keyboardWillChangeFrameTo: endFrame, intent: .show)
        }
    }
    
    func inputAccessoryViewSuperviewFrameDidChange(to newFrame: CGRect) {
        guard isShowingKeyboard else {
            return
        }
        if justChangedInputAccessoryViewHeight {
            justChangedInputAccessoryViewHeight = false
        } else if !keyboardFrameIsInvisible(newFrame) {
            delegate?.conversationKeyboardManager(self, keyboardWillChangeFrameTo: newFrame, intent: .changeFrame)
        }
    }
    
    private func keyboardFrameIsInvisible(_ frame: CGRect) -> Bool {
        return frame.origin.y == UIApplication.shared.keyWindow?.frame.height
    }
    
}

extension ConversationKeyboardManager {
    
    enum KeyboardIntent {
        case show
        case hide
        case changeFrame
    }
    
    class FrameObservingInputAccessoryView: UIView {
        
        weak var manager: ConversationKeyboardManager?
        
        private var observation: NSKeyValueObservation?
        
        required init?(coder aDecoder: NSCoder) {
            super.init(coder: aDecoder)
            prepare()
        }
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            prepare()
        }
        
        convenience init(height: CGFloat) {
            let frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: height)
            self.init(frame: frame)
        }
        
        override func willMove(toSuperview newSuperview: UIView?) {
            observation?.invalidate()
            observation = newSuperview?.layer.observe(\.position, options: [.initial, .new]) { (layer, _) in
                self.manager?.inputAccessoryViewSuperviewFrameDidChange(to: layer.frame)
            }
            super.willMove(toSuperview: newSuperview)
        }
        
        private func prepare() {
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }
        
    }
    
}
