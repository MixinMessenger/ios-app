import Foundation
import UIKit
import Alamofire

class UrlWindow: BottomSheetView {

    @IBOutlet weak var loadingView: UIActivityIndicatorView!
    @IBOutlet weak var errorLabel: UILabel!
    @IBOutlet weak var containerView: UIView!

    @IBOutlet weak var contentHeightConstraint: NSLayoutConstraint!

    private var animationPushOriginPoint: CGPoint {
        return CGPoint(x: self.bounds.size.width + self.popupView.bounds.size.width, y: self.popupView.center.y)
    }
    private var animationPushEndPoint: CGPoint {
        return CGPoint(x: self.bounds.size.width-(self.popupView.bounds.size.width * 0.5), y: self.popupView.center.y)
    }

    private lazy var groupView = GroupView.instance()
    private lazy var loginView = LoginView.instance()
    private lazy var payView = PayView.instance()

    private(set) var fromWeb = false
    private var showLoginView = false
    private var interceptDismiss = false

    class func checkUrl(url: URL, fromWeb: Bool = false, clearNavigationStack: Bool = true, checkLastWindow: Bool = true) -> Bool {
        if checkLastWindow && UIApplication.shared.keyWindow?.subviews.last is UrlWindow {
            return false
        }
        switch MixinURL(url: url) {
        case let .codes(code):
            return checkCodesUrl(code, fromWeb: fromWeb, clearNavigationStack: clearNavigationStack)
        case .pay:
            return checkPayUrl(url: url, fromWeb: fromWeb)
        case .unknown:
            return false
        }
    }

    override func presentPopupControllerAnimated() {
        if fromWeb {
            contentHeightConstraint.constant = 484
            self.layoutIfNeeded()
            windowBackgroundColor = UIColor.clear
        }
        super.presentPopupControllerAnimated()
        loadingView.startAnimating()
        loadingView.isHidden = false
        errorLabel.isHidden = true
    }

    override func dismissPopupControllerAnimated() {
        if interceptDismiss {
            if payView.processing {
                return
            }
            if payView.pinField.isFirstResponder {
                payView.pinField.resignFirstResponder()
                return
            }
        }
        if showLoginView {
            loginView.onWindowWillDismiss()
        }
        super.dismissPopupControllerAnimated()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NotificationCenter.default.postOnMain(name: .WindowDidDisappear)
        }
    }

    override func getAnimationStartPoint() -> CGPoint {
        return fromWeb ? animationPushOriginPoint : super.getAnimationStartPoint()
    }

    override func getAnimationEndPoint() -> CGPoint {
        return fromWeb ? animationPushEndPoint : super.getAnimationEndPoint()
    }

    class func instance() -> UrlWindow {
        return Bundle.main.loadNibNamed("UrlWindow", owner: nil, options: nil)?.first as! UrlWindow
    }
}

extension UrlWindow {

    class func checkCodesUrl(_ codeId: String, fromWeb: Bool = false, clearNavigationStack: Bool) -> Bool {
        guard !codeId.isEmpty, UUID(uuidString: codeId) != nil else {
            return false
        }

        UrlWindow.instance().presentPopupControllerAnimated(codeId: codeId, fromWeb: fromWeb, clearNavigationStack: clearNavigationStack)
        return true
    }

    private func presentPopupControllerAnimated(codeId: String, fromWeb: Bool = false, clearNavigationStack: Bool) {
        self.fromWeb = fromWeb
        presentPopupControllerAnimated()

        UserAPI.shared.codes(codeId: codeId) { [weak self](result) in
            guard let weakSelf = self, weakSelf.isShowing else {
                return
            }

            switch result {
            case let .success(code):
                if let user = code.user {
                    UserDAO.shared.updateUsers(users: [user])
                    weakSelf.dismissPopupControllerAnimated()
                    if user.userId == AccountAPI.shared.account?.user_id {
                        let vc = MyProfileViewController.instance()
                        if clearNavigationStack {
                            UIApplication.rootNavigationController()?.pushViewController(withBackRoot: vc)
                        } else {
                            UIApplication.rootNavigationController()?.pushViewController(vc, animated: true)
                        }
                    } else {
                        UserWindow.instance().updateUser(user: UserItem.createUser(from: user)).presentView()
                    }
                } else if let authorization = code.authorization {
                    weakSelf.load(authorization: authorization)
                } else if let conversation = code.conversation {
                    weakSelf.load(conversation: conversation, codeId: codeId)
                }
            case let .failure(error, _):
                if error.code == 404 {
                    weakSelf.failedHandler(Localized.CODE_RECOGNITION_FAIL_TITLE)
                } else {
                    weakSelf.failedHandler(error.kind.localizedDescription ?? error.description)
                }
            }
        }
    }

    private func autoDismissWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let weakSelf = self, weakSelf.isShowing else {
                return
            }
            weakSelf.dismissPopupControllerAnimated()
        }
    }

    private func load(authorization: AuthorizationResponse) {
        DispatchQueue.global().async { [weak self] in
            let assets = AssetDAO.shared.getAvailableAssets()
            DispatchQueue.main.async {
                guard let weakSelf = self, weakSelf.isShowing else {
                    return
                }

                weakSelf.showLoginView = true
                if let webWindow = UIApplication.shared.keyWindow?.subviews.first(where: { $0 is WebWindow }) as? WebWindow {
                    weakSelf.contentHeightConstraint.constant = webWindow.webViewWrapperView.frame.height + webWindow.titleView.frame.height
                } else {
                    weakSelf.contentHeightConstraint.constant = 484
                }
                weakSelf.layoutIfNeeded()
                
                weakSelf.containerView.addSubview(weakSelf.loginView)
                weakSelf.loginView.snp.makeConstraints({ (make) in
                    make.edges.equalToSuperview()
                })
                weakSelf.loginView.render(authInfo: authorization, assets: assets, superView: weakSelf)
                weakSelf.successHandler()

                UIView.animate(withDuration: 0.15, animations: {
                    weakSelf.layoutIfNeeded()
                })
            }
        }
    }

    private func load(conversation: ConversationResponse, codeId: String) {
        DispatchQueue.global().async { [weak self] in
            let subParticipants: ArraySlice<ParticipantResponse> = conversation.participants.prefix(4)
            let accountUserId = AccountAPI.shared.accountUserId
            let conversationId = conversation.conversationId
            let alreadyInTheGroup = conversation.participants.first(where: { $0.userId == accountUserId }) != nil
            let userIds = subParticipants.map{ $0.userId }
            var participants = [ParticipantUser]()
            switch UserAPI.shared.showUsers(userIds: userIds) {
            case let .success(users):
                participants = users.flatMap { ParticipantUser.createParticipantUser(conversationId: conversationId, user: $0) }
            case let .failure(error):
                DispatchQueue.main.async {
                    self?.failedHandler(error.localizedDescription)
                }
                return
            }
            var creatorUser = UserDAO.shared.getUser(userId: conversation.creatorId)
            if creatorUser == nil {
                switch UserAPI.shared.showUser(userId: conversation.creatorId) {
                case let .success(user):
                    creatorUser = UserItem.createUser(from: user)
                case let .failure(error):
                    DispatchQueue.main.async {
                        self?.failedHandler(error.localizedDescription)
                    }
                    return
                }
            }

            DispatchQueue.main.async {
                guard let weakSelf = self, let ownerUser = creatorUser, weakSelf.isShowing else {
                    return
                }
                weakSelf.containerView.addSubview(weakSelf.groupView)
                weakSelf.groupView.snp.makeConstraints({ (make) in
                    make.edges.equalToSuperview()
                })
                weakSelf.groupView.render(codeId: codeId, conversation: conversation, ownerUser: ownerUser, participants: participants, alreadyInTheGroup: alreadyInTheGroup, superView: weakSelf)
                weakSelf.successHandler()

                weakSelf.contentHeightConstraint.constant = 369
                UIView.animate(withDuration: 0.15, animations: {
                    weakSelf.layoutIfNeeded()
                })
            }
        }
    }

    private func failedHandler(_ errorMsg: String) {
        loadingView.stopAnimating()
        loadingView.isHidden = true
        errorLabel.text = errorMsg
        errorLabel.isHidden = false
        autoDismissWindow()
    }

    private func successHandler() {
        loadingView.stopAnimating()
        loadingView.isHidden = true
        errorLabel.isHidden = true
    }
}

extension UrlWindow {

    func presentPopupControllerAnimated(assetId: String, counterUserId: String, amount: String, traceId: String, memo: String, fromWeb: Bool = false) {
        self.fromWeb = fromWeb
        presentPopupControllerAnimated()
        AssetAPI.shared.payments(assetId: assetId, counterUserId: counterUserId, amount: amount, traceId: traceId) { [weak self](result) in
            guard let weakSelf = self, weakSelf.isShowing else {
                return
            }
            switch result {
            case let .success(payment):
                guard payment.status != PaymentStatus.paid.rawValue else {
                    weakSelf.failedHandler(Localized.TRANSFER_PAID)
                    return
                }
                if PayWindow.shared.isShowing {
                    PayWindow.shared.removeFromSuperview()
                }

                weakSelf.interceptDismiss = true

                weakSelf.containerView.addSubview(weakSelf.payView)
                weakSelf.payView.snp.makeConstraints({ (make) in
                    make.edges.equalToSuperview()
                })
                
                weakSelf.payView.render(asset: payment.asset, user: UserItem.createUser(from: payment.recipient), amount: amount, memo: memo, trackId: traceId, superView: weakSelf)
                weakSelf.successHandler()
            case let .failure(error, _):
                weakSelf.failedHandler(error.kind.localizedDescription ?? error.description)
            }
        }
    }

    class func checkPayUrl(url: URL, fromWeb: Bool = false) -> Bool {
        guard let query = url.getKeyVals() else {
            return false
        }
        guard let recipientId = query["recipient"], let assetId = query["asset"], let amount = query["amount"], let traceId = query["trace"] else {
            return false
        }
        guard !recipientId.isEmpty && UUID(uuidString: recipientId) != nil && !assetId.isEmpty && UUID(uuidString: assetId) != nil && !traceId.isEmpty && UUID(uuidString: traceId) != nil && !amount.isEmpty else {
            return false
        }

        var memo = query["memo"]
        if let urlDecodeMemo = memo?.removingPercentEncoding {
            memo = urlDecodeMemo
        }
        UrlWindow.instance().presentPopupControllerAnimated(assetId: assetId, counterUserId: recipientId, amount: amount, traceId: traceId, memo: memo ?? "", fromWeb: fromWeb)

        return true
    }

}
