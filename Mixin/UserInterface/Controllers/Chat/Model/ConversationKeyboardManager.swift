import UIKit

protocol ConversationKeyboardManagerDelegate: class {
    func conversationKeyboardManagerScrollViewIsTracking(_ manager: ConversationKeyboardManager) -> Bool
    func conversationKeyboardManager(_ manager: ConversationKeyboardManager, keyboardWillChangeFrameTo newFrame: CGRect, intent: ConversationKeyboardManager.KeyboardIntent)
}

class ConversationKeyboardManager {
    
    static var lastKeyboardHeight: CGFloat = ScreenSize.defaultKeyboardHeight
    
    let inputAccessoryView: FrameObservingInputAccessoryView
    
    private(set) var isShowingKeyboard = false
    
    weak var delegate: ConversationKeyboardManagerDelegate?
    
    var inputAccessoryViewHeight: CGFloat {
        get {
            return inputAccessoryView.frame.height
        }
        set {
            guard let heightConstraint = inputAccessoryView.constraints.filter({ ($0.firstItem as? UIView) == inputAccessoryView && $0.firstAttribute == .height }).first, heightConstraint.constant != newValue else {
                return
            }
            heightConstraint.constant = newValue
            inputAccessoryView.frame.size.height = newValue
        }
    }
    
    init() {
        inputAccessoryView = FrameObservingInputAccessoryView(height: 0)
        inputAccessoryView.manager = self
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func keyboardWillChangeFrame(_ notification: Notification) {
        guard let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
            return
        }
        if keyboardFrameIsInvisible(endFrame) && isShowingKeyboard {
            isShowingKeyboard = false
            delegate?.conversationKeyboardManager(self, keyboardWillChangeFrameTo: endFrame, intent: .hide)
        } else if !keyboardFrameIsInvisible(endFrame) && !isShowingKeyboard {
            isShowingKeyboard = true
            delegate?.conversationKeyboardManager(self, keyboardWillChangeFrameTo: endFrame, intent: .show)
            updateLastKeyboardHeight(keyboardFrame: endFrame)
        } else if endFrame.height < ScreenSize.minReasonableKeyboardHeight, let delegate = delegate {
            if delegate.conversationKeyboardManagerScrollViewIsTracking(self) {
                delegate.conversationKeyboardManager(self, keyboardWillChangeFrameTo: endFrame, intent: .hide)
            }
        }
    }
    
    func inputAccessoryViewSuperviewFrameDidChange(to newFrame: CGRect) {
        guard isShowingKeyboard, !keyboardFrameIsInvisible(newFrame), let delegate = delegate else {
            return
        }
        if delegate.conversationKeyboardManagerScrollViewIsTracking(self) {
            delegate.conversationKeyboardManager(self, keyboardWillChangeFrameTo: newFrame, intent: .interactivelyChangeFrame)
        } else {
            delegate.conversationKeyboardManager(self, keyboardWillChangeFrameTo: newFrame, intent: .changeFrame)
            updateLastKeyboardHeight(keyboardFrame: newFrame)
        }
    }
    
    private func keyboardFrameIsInvisible(_ frame: CGRect) -> Bool {
        return ceil(frame.origin.y) >= UIScreen.main.bounds.height
    }
    
    private func updateLastKeyboardHeight(keyboardFrame frame: CGRect) {
        ConversationKeyboardManager.lastKeyboardHeight = max(ScreenSize.minReasonableKeyboardHeight, frame.height - inputAccessoryView.frame.height)
    }
    
}

extension ConversationKeyboardManager {
    
    enum KeyboardIntent {
        case show
        case hide
        case changeFrame
        case interactivelyChangeFrame
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
