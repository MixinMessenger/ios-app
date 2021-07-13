import UIKit
import WebKit
import Alamofire
import MixinServices

class MixinWebViewController: WebViewController {
    
    @IBOutlet weak var loadFailLabel: UILabel!
    @IBOutlet weak var contactDeveloperButton: UIButton!
    
    private enum HandlerName {
        static let mixinContext = "MixinContext"
        static let reloadTheme = "reloadTheme"
        static let playlist = "playlist"
    }
    
    weak var associatedClip: Clip?
    
    override var webViewConfiguration: WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.dataDetectorTypes = .all
        config.preferences = WKPreferences()
        config.preferences.minimumFontSize = 12
        config.preferences.javaScriptEnabled = true
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .video
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.userContentController.addUserScript(Script.disableImageSelection)
        config.userContentController.add(self, name: HandlerName.mixinContext)
        config.userContentController.add(self, name: HandlerName.reloadTheme)
        config.userContentController.add(self, name: HandlerName.playlist)
        config.applicationNameForUserAgent = "Mixin/\(Bundle.main.shortVersion)"
        return config
    }
    
    private let loadingIndicator = AppLoadingIndicatorView(frame: .zero)
    
    private(set) var context: Context!
    
    private lazy var suspicousLinkView = R.nib.suspiciousLinkView(owner: self)!
    private lazy var loadingFailureView: UIView = {
        let view = R.nib.webLoadingFailureView(owner: self)!
        loadingFailureViewIfLoaded = view
        return view
    }()
    
    private weak var loadingFailureViewIfLoaded: UIView?
    
    private var isMessageHandlerAdded = true
    private var webViewTitleObserver: NSKeyValueObservation?
    
    deinit {
        #if DEBUG
        print("\(self) deinited")
        #endif
    }
    
    class func instance(with context: Context) -> MixinWebViewController {
        let vc = MixinWebViewController(nib: R.nib.fullscreenPopupView)
        vc.context = context
        return vc
    }
    
    class func presentInstance(with context: Context, asChildOf parent: UIViewController) {
        let vc = Self.instance(with: context)
        vc.presentAsChild(of: parent, completion: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        contentView.insertSubview(loadingIndicator, aboveSubview: webContentView)
        loadingIndicator.snp.makeConstraints { (make) in
            make.center.equalToSuperview()
        }
        loadingIndicator.startAnimating()
        showPageTitleConstraint.priority = context.isImmersive ? .defaultLow : .defaultHigh
        webView.navigationDelegate = self
        webView.uiDelegate = self
        loadWebView()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !isMessageHandlerAdded {
            let controller = webView.configuration.userContentController
            controller.add(self, name: HandlerName.mixinContext)
            controller.add(self, name: HandlerName.reloadTheme)
            controller.add(self, name: HandlerName.playlist)
            isMessageHandlerAdded = true
        }
    }
    
    override func popupDidDismissAsChild() {
        super.popupDidDismissAsChild()
        if associatedClip == nil {
            removeAllMessageHandlers()
        }
    }
    
    override func moreAction(_ sender: Any) {
        let floatAction: WebMoreMenuViewController.MenuItem
        if associatedClip == nil {
            floatAction = .float
        } else {
            floatAction = .cancelFloat
        }
        let sections: [[WebMoreMenuViewController.MenuItem]]
        switch context.style {
        case .app:
            sections = [[.share], [floatAction], [.about, .refresh]]
        case .webPage:
            sections = [[.share], [floatAction], [.copyLink, .refresh, .openInSafari]]
        }
        let more = WebMoreMenuViewController(sections: sections)
        more.overrideStatusBarStyle = preferredStatusBarStyle
        more.titleView.titleLabel.text = titleLabel.text
        switch context.style {
        case let .app(app, _):
            more.titleView.subtitleLabel.text = app.appNumber
            more.titleView.imageView.isHidden = false
            more.titleView.imageView.setImage(app: app)
        case .webPage:
            more.titleView.subtitleLabel.text = (context.initialUrl.host ?? "") + context.initialUrl.path
            more.titleView.imageView.isHidden = true
        }
        more.delegate = self
        present(more, animated: true, completion: nil)
    }
    
    @IBAction func continueAction(_ sender: Any) {
        suspicousLinkView.removeFromSuperview()
        loadNormalUrl()
    }
    
    @IBAction func reloadAction(_ sender: Any) {
        loadingFailureViewIfLoaded?.removeFromSuperview()
        if let currentUrl = webView.url {
            let request = URLRequest(url: currentUrl,
                                     cachePolicy: .reloadIgnoringLocalCacheData,
                                     timeoutInterval: 10)
            self.webView.load(request)
        } else {
            loadWebView()
        }
    }
    
    @IBAction func contactDeveloperAction(_ sender: Any) {
        guard case let .app(app, _) = context.style else {
            return
        }
        let hud = Hud()
        hud.show(style: .busy, text: "", on: AppDelegate.current.mainWindow)
        DispatchQueue.global().async { [weak self] in
            guard let developerUserId = Self.syncUser(userId: app.appId, hud: hud)?.appCreatorId else {
                return
            }
            guard let developUser = Self.syncUser(userId: developerUserId, hud: hud) else {
               return
            }
            DispatchQueue.main.async {
                hud.hide()
                UIApplication.homeNavigationController?.pushViewController(withBackRoot: ConversationViewController.instance(ownerUser: developUser))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self?.dismissAsChild(animated: true)
                }
            }
        }
    }
    
    func removeAllMessageHandlers() {
        guard isViewLoaded && isMessageHandlerAdded else {
            return
        }
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: HandlerName.mixinContext)
        controller.removeScriptMessageHandler(forName: HandlerName.reloadTheme)
        controller.removeScriptMessageHandler(forName: HandlerName.playlist)
        isMessageHandlerAdded = false
    }
    
}

extension MixinWebViewController: WKNavigationDelegate {
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        
        if isViewLoaded && (UrlWindow.checkUrl(url: url, webContext: context) || UrlWindow.checkPayUrl(url: url.absoluteString)) {
            decisionHandler(.cancel)
            return
        } else if "file" == url.scheme {
            decisionHandler(.allow)
            return
        }
        
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            decisionHandler(.cancel)
            return
        }
        
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard !loadingIndicator.isHidden else {
            return
        }
        loadingIndicator.stopAnimating()
        loadingIndicator.isHidden = true
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.isOpaque = true
        reloadTheme(webView: webView)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        guard let failURL = nsError.userInfo["NSErrorFailingURLKey"] as? URL, let host = failURL.host else {
            return
        }
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorInternationalRoamingOff, NSURLErrorDataNotAllowed, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
            if loadingFailureView.superview == nil {
                contentView.insertSubview(loadingFailureView, belowSubview: pageControlView)
                loadingFailureView.snp.makeConstraints { make in
                    make.leading.trailing.equalToSuperview()
                    make.top.bottom.equalTo(contentView.safeAreaLayoutGuide)
                }
            }
            loadFailLabel.text = R.string.localizable.web_cannot_reached_desc(host)
            if case .app = context.style {
                contactDeveloperButton.isHidden = false
            } else {
                contactDeveloperButton.isHidden = true
            }
        default:
            break
        }
    }
}

extension MixinWebViewController: WKUIDelegate {
    
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        if prompt == HandlerName.mixinContext + ".getContext()" {
            completionHandler(context.appContextString)
        } else {
            completionHandler("")
        }
    }
    
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if !(navigationAction.targetFrame?.isMainFrame ?? false) {
            webView.load(navigationAction.request)
        }
        return nil
    }
    
}

extension MixinWebViewController: WKScriptMessageHandler {
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case HandlerName.reloadTheme:
            reloadTheme(webView: webView)
        case HandlerName.playlist:
            if let body = message.body as? [String] {
                let playlist = body.compactMap(PlaylistItem.init)
                if !playlist.isEmpty {
                    PlaylistManager.shared.play(index: 0, in: playlist, source: .remote)
                }
            }
        default:
            break
        }
    }
    
}

extension MixinWebViewController: WebMoreMenuControllerDelegate {
    
    func webMoreMenuViewController(_ controller: WebMoreMenuViewController, didSelect item: WebMoreMenuViewController.MenuItem) {
        
        func handle() {
            let url = webView.url ?? .blank
            switch item {
            case .share:
                switch context.style {
                case .app:
                    if context.isShareable ?? true {
                        shareAppCardAction(currentUrl: url)
                    } else {
                        presentGotItAlertController(title: R.string.localizable.chat_forward_invalid_link_not_shareable())
                    }
                case .webPage:
                    shareUrlAction(currentUrl: url)
                }
            case .float:
                if let switcher = UIApplication.homeContainerViewController?.clipSwitcher {
                    if switcher.clips.count < ClipSwitcher.maxNumber {
                        dismissAsChild(animated: true) {
                            switcher.appendClip(with: self)
                        }
                    } else {
                        let text = R.string.localizable.clip_hint_did_reach_max("\(ClipSwitcher.maxNumber)")
                        showAutoHiddenHud(style: .error, text: text)
                    }
                }
            case .cancelFloat:
                if let clip = associatedClip,
                   let switcher = UIApplication.homeContainerViewController?.clipSwitcher,
                   let index = switcher.clips.firstIndex(of: clip) {
                    switcher.removeClip(at: index)
                }
                associatedClip = nil
            case .about:
                aboutAction()
            case .copyLink:
                copyAction(currentUrl: url)
            case .refresh:
                reloadAction(controller)
            case .openInSafari:
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        
        controller.dismiss(animated: true, completion: handle)
    }
    
}

extension MixinWebViewController {
    
    private func loadNormalUrl() {
        webViewTitleObserver = webView.observe(\.title, options: [.initial, .new], changeHandler: { [weak self] (webView, _) in
            guard let weakSelf = self, case .webPage = weakSelf.context.style else {
                return
            }
            self?.titleLabel.text = webView.title
        })
        webView.load(URLRequest(url: context.initialUrl))
    }

    private func loadAppUrl(title: String, iconUrl: URL?) {
        titleLabel.text = title
        if let iconUrl = iconUrl {
            titleImageView.isHidden = false
            titleImageView.sd_setImage(with: iconUrl, completed: nil)
        }
        if !context.extraParams.isEmpty, var components = URLComponents(url: context.initialUrl, resolvingAgainstBaseURL: true) {
            var queryItems: [URLQueryItem] = components.queryItems ?? []
            for item in context.extraParams {
                queryItems.append(URLQueryItem(name: item.key, value: item.value))
            }
            components.queryItems = queryItems
            webView.load(URLRequest(url: components.url ?? context.initialUrl))
        } else {
            webView.load(URLRequest(url: context.initialUrl))
        }
    }
    
    private func loadWebView() {
        switch context.style {
        case .webPage:
            loadNormalUrl()
        case let .app(app, isHomeUrl):
            let appId = app.appId
            let title = app.name
            let iconUrl = URL(string: app.iconUrl)
            if isHomeUrl {
                loadAppUrl(title: title, iconUrl: iconUrl)
            } else {
                let validUrl = context.initialUrl.absoluteString + "/"
                DispatchQueue.global().async { [weak self] in
                    var app = AppDAO.shared.getApp(appId: appId)
                    if app == nil || !(app?.resourcePatterns?.contains(where: validUrl.hasPrefix) ?? false) {
                        if case let .success(response) = UserAPI.showUser(userId: appId) {
                            UserDAO.shared.updateUsers(users: [response])
                            app = response.app
                        }
                    }
                    DispatchQueue.main.async {
                        guard let self = self else {
                            return
                        }
                        if app?.resourcePatterns?.contains(where: validUrl.hasPrefix) ?? false {
                            self.loadAppUrl(title: title, iconUrl: iconUrl)
                        } else {
                            if self.suspicousLinkView.superview == nil {
                                self.contentView.insertSubview(self.suspicousLinkView,
                                                               belowSubview: self.pageControlView)
                                self.suspicousLinkView.snp.makeConstraints { make in
                                    make.leading.trailing.equalToSuperview()
                                    make.top.bottom.equalTo(self.contentView.safeAreaLayoutGuide)
                                }
                            }
                            self.context.style = .webPage
                            self.context.isImmersive = false
                        }
                    }
                }
            }
        }
    }
    
    private func reloadTheme(webView: WKWebView) {
        webView.evaluateJavaScript(Script.getThemeColor) { [weak self] (result, error) in
            guard let colorString = result as? String else {
                return
            }
            let color = UIColor(hexString: colorString) ?? .background
            self?.updateBackground(pageThemeColor: color)
        }
    }
    
    private func aboutAction() {
        guard case let .app(app, _) = context.style else {
            return
        }
        let appId = app.appId
        DispatchQueue.global().async {
            var userItem = UserDAO.shared.getUser(userId: appId)
            var updateUserFromRemoteAfterReloaded = true
            
            if userItem == nil, case let .success(response) = UserAPI.showUser(userId: appId) {
                updateUserFromRemoteAfterReloaded = false
                userItem = UserItem.createUser(from: response)
                UserDAO.shared.updateUsers(users: [response])
            }
            
            guard let user = userItem else {
                return
            }
            DispatchQueue.main.async {
                let vc = UserProfileViewController(user: user)
                vc.updateUserFromRemoteAfterReloaded = updateUserFromRemoteAfterReloaded
                UIApplication.homeContainerViewController?.present(vc, animated: true, completion: nil)
            }
        }
    }
    
    private func copyAction(currentUrl: URL) {
        UIPasteboard.general.string = currentUrl.absoluteString
        showAutoHiddenHud(style: .notification, text: Localized.TOAST_COPIED)
    }

    private func shareAppCardAction(currentUrl: URL) {
        guard case let .app(app, _) = context.style else {
            return
        }
        let appId = app.appId
        let isShareable = context.isShareable
        var cardTitle = app.name
        if let webTitle = webView.title, !webTitle.trim().isEmpty {
            cardTitle = webTitle.trim()
        }

        DispatchQueue.global().async { [weak self] in
            var app = AppDAO.shared.getApp(appId: appId)
            if app == nil {
                if case let .success(response) = UserAPI.showUser(userId: appId) {
                    UserDAO.shared.updateUsers(users: [response])
                    app = response.app
                }
            }
            
            DispatchQueue.main.async {
                let validUrl = currentUrl.absoluteString + "/"
                if let app = app, let iconUrl = URL(string: app.iconUrl), app.resourcePatterns?.contains(where: validUrl.hasPrefix) ?? false {
                    let appCard = AppCardData(appId: app.appId,
                                              iconUrl: iconUrl,
                                              title: String(cardTitle.prefix(32)),
                                              description: String(app.name.prefix(64)),
                                              action: currentUrl,
                                              updatedAt: nil,
                                              isShareable: isShareable)
                    let vc = MessageReceiverViewController.instance(content: .appCard(appCard))
                    self?.navigationController?.pushViewController(vc, animated: true)
                } else {
                    let vc = MessageReceiverViewController.instance(content: .text(currentUrl.absoluteString))
                    self?.navigationController?.pushViewController(vc, animated: true)
                }
            }
        }
    }

    private func shareUrlAction(currentUrl: URL) {
        guard case .webPage = context.style else {
            return
        }
        
        let vc = MessageReceiverViewController.instance(content: .text(currentUrl.absoluteString))
        let navigationController = self.navigationController ?? UIApplication.homeNavigationController
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private static func syncUser(userId: String, hud: Hud) -> UserItem? {
        if let user = UserDAO.shared.getUser(userId: userId) {
            return user
        } else {
            switch UserAPI.showUser(userId: userId) {
            case let .success(userItem):
                let user = UserItem.createUser(from: userItem)
                UserDAO.shared.updateUsers(users: [userItem])
                return user
            case let .failure(error):
                DispatchQueue.main.async {
                    let text = error.localizedDescription(overridingNotFoundDescriptionWith: R.string.localizable.user_not_found())
                    hud.set(style: .error, text: text)
                    hud.scheduleAutoHidden()
                }
                return nil
            }
        }
    }
    
}

extension MixinWebViewController {
    
    enum Script {
        static let getThemeColor = """
            function getColor() {
                const metas = document.getElementsByTagName('meta');
                for (var i = metas.length - 1; i >= 0; i--) {
                    if (metas[i].getAttribute('name') === 'theme-color' && metas[i].hasAttribute('content')) {
                        return metas[i].getAttribute('content');
                    }
                }
                return '';
            }
            getColor();
        """
        static let disableImageSelection: WKUserScript = {
            let string = """
                var style = document.createElement('style');
                style.innerHTML = 'img { -webkit-user-select: none; -webkit-touch-callout: none; }';
                document.head.appendChild(style)
            """
            return WKUserScript(source: string,
                                injectionTime: .atDocumentEnd,
                                forMainFrameOnly: true)
        }()
    }
    
    struct Context {
        
        enum Style {
            case webPage
            case app(app: App, isHomeUrl: Bool)
        }
        
        let conversationId: String
        let initialUrl: URL
        let isShareable: Bool?

        var style: Style
        var isImmersive: Bool
        var extraParams: [String: String] = [:]
        
        var appContextString: String {
            let ctx: [String: Any] = [
                "app_version": Bundle.main.shortVersion,
                "immersive": isImmersive,
                "appearance": UserInterfaceStyle.current.rawValue,
                "currency": Currency.current.code,
                "locale": "\(Locale.current.languageCode ?? "")-\(Locale.current.regionCode ?? "")",
                "platform": "iOS",
                "conversation_id": conversationId
            ]
            if let data = try? JSONSerialization.data(withJSONObject: ctx, options: []), let string = String(data: data, encoding: .utf8) {
                return string
            } else {
                return ""
            }
        }
        
        init(conversationId: String, app: App, shareable: Bool? = nil, extraParams: [String: String] = [:]) {
            if conversationId.isEmpty {
                self.conversationId = ConversationDAO.shared.makeConversationId(userId: myUserId, ownerUserId: app.appId)
            } else {
                self.conversationId = conversationId
            }
            self.initialUrl = URL(string: app.homeUri) ?? .blank
            self.isShareable = shareable
            self.style = .app(app: app, isHomeUrl: true)
            self.isImmersive = app.capabilities?.contains("IMMERSIVE") ?? false
            self.extraParams = extraParams
        }
        
        init(conversationId: String, initialUrl: URL, shareable: Bool? = nil) {
            self.conversationId = conversationId
            self.initialUrl = initialUrl
            self.isShareable = shareable
            self.style = .webPage
            self.isImmersive = false
        }
        
        init(conversationId: String, url: URL, app: App, shareable: Bool? = nil) {
            self.conversationId = conversationId
            self.initialUrl = url
            self.isShareable = shareable
            self.style = .app(app: app, isHomeUrl: false)
            self.isImmersive = app.capabilities?.contains("IMMERSIVE") ?? false
        }
        
    }
    
}
