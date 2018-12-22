import UIKit

class PeerSelectionViewController: UIViewController, ContainerViewControllerDelegate {
    
    class var usesModernStyle: Bool {
        return false
    }
    
    enum Content {
        case chatsAndContacts
        case contacts
        case transferReceivers
        case catalogedContacts
    }
    
    let tableView = UITableView()
    
    var searchBoxView: (UIView & SearchBox)!
    
    var allowsMultipleSelection: Bool {
        return true
    }
    
    var content: Content {
        return .chatsAndContacts
    }
    
    private var headerTitles = [String]()
    private var peers = [[Peer]]()
    private var searchResults = [Peer]()
    private var selections = Set<Peer>() {
        didSet {
            container?.rightButton.isEnabled = selections.count > 0
        }
    }
    private var sortedSelections = [Peer]()
    
    private var isSearching: Bool {
        return !searchBoxView.textField.text.isEmpty
    }
    
    private var searchBoxViewClass: (UIView & SearchBox).Type {
        return type(of: self).usesModernStyle ? ModernSearchBoxView.self : LegacySearchBoxView.self
    }
    
    override func loadView() {
        view = UIView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        searchBoxView = searchBoxViewClass.init(frame: CGRect(x: 0, y: 0, width: 375, height: 70))
        view.addSubview(searchBoxView)
        view.addSubview(tableView)
        searchBoxView.snp.makeConstraints { (make) in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(searchBoxView.height)
        }
        tableView.snp.makeConstraints { (make) in
            make.top.equalTo(searchBoxView.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        searchBoxView.textField.addTarget(self,
                                          action: #selector(search(_:)),
                                          for: .editingChanged)
        tableView.allowsMultipleSelection = allowsMultipleSelection
        tableView.rowHeight = 60
        tableView.register(UINib(nibName: "PeerCell", bundle: .main),
                           forCellReuseIdentifier: ReuseId.cell)
        tableView.register(GeneralTableViewHeader.self,
                           forHeaderFooterViewReuseIdentifier: ReuseId.header)
        tableView.tableFooterView = UIView()
        tableView.dataSource = self
        tableView.delegate = self
        reloadData()
    }
    
    @objc func search(_ sender: Any) {
        let keyword = (searchBoxView.textField.text ?? "").uppercased()
        if keyword.isEmpty {
            searchResults = []
        } else {
            var unique = Set<Peer>()
            searchResults = peers
                .flatMap({ $0 })
                .filter({ $0.name.uppercased().contains(keyword) })
                .filter({ unique.insert($0).inserted })
        }
        tableView.reloadData()
        reloadSelections()
    }
    
    func work(selections: [Peer]) {
        
    }
    
    func popToConversationWithLastSelection() {
        if let peer = sortedSelections.last {
            let vc: ConversationViewController
            switch peer.item {
            case .group(let conversation):
                vc = ConversationViewController.instance(conversation: conversation)
            case .user(let user):
                vc = ConversationViewController.instance(ownerUser: user)
            }
            navigationController?.pushViewController(withBackRoot: vc)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    // MARK: ContainerViewControllerDelegate
    func prepareBar(rightButton: StateResponsiveButton) {
        rightButton.setTitleColor(.systemTint, for: .normal)
    }
    
    func barRightButtonTappedAction() {
        work(selections: sortedSelections)
    }
    
    func textBarRightButton() -> String? {
        return nil
    }
    
}

extension PeerSelectionViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard !peers.isEmpty else {
            return 0
        }
        return isSearching ? searchResults.count : peers[section].count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ReuseId.cell) as! PeerCell
        let peer = self.peer(at: indexPath)
        cell.render(peer: peer)
        cell.supportsMultipleSelection = allowsMultipleSelection
        cell.usesModernStyle = type(of: self).usesModernStyle
        return cell
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return isSearching ? 1 : peers.count
    }
    
}

extension PeerSelectionViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard !isSearching, !headerTitles.isEmpty else {
            return nil
        }
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: ReuseId.header) as! GeneralTableViewHeader
        header.label.text = headerTitles[section]
        return header
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if isSearching {
            return .leastNormalMagnitude
        } else if !headerTitles.isEmpty {
            return peers[section].isEmpty ? .leastNormalMagnitude : 30
        } else {
            return .leastNormalMagnitude
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let peer = self.peer(at: indexPath)
        if allowsMultipleSelection {
            let inserted = selections.insert(peer).inserted
            if inserted {
                sortedSelections.append(peer)
            }
            reloadSelections()
        } else {
            work(selections: [peer])
        }
    }
    
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        let peer = self.peer(at: indexPath)
        selections.remove(peer)
        if let index = sortedSelections.firstIndex(of: peer) {
            sortedSelections.remove(at: index)
        }
        reloadSelections()
    }
    
}

extension PeerSelectionViewController: UIScrollViewDelegate {
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if searchBoxView.textField.isFirstResponder {
            searchBoxView.textField.resignFirstResponder()
        }
    }
    
}

extension PeerSelectionViewController {
    
    private enum ReuseId {
        static let cell = "cell"
        static let header = "header"
    }
    
    private static func catalogedPeers(from users: [UserItem]) -> (titles: [String], peers: [[Peer]]) {
        
        class ObjcAccessiblePeer: NSObject{
            @objc let fullName: String
            let peer: Peer
            
            init(user: UserItem) {
                self.fullName = user.fullName
                self.peer = Peer(user: user)
                super.init()
            }
        }
        
        let objcAccessibleUsers = users.map(ObjcAccessiblePeer.init)
        let (titles, objcUsers) = UILocalizedIndexedCollation
            .current()
            .catalogue(objcAccessibleUsers, usingSelector: #selector(getter: ObjcAccessiblePeer.fullName))
        let peers = objcUsers.map({ $0.map({ $0.peer }) })
        return (titles, peers)
    }
    
    private func peer(at indexPath: IndexPath) -> Peer {
        if isSearching {
            return searchResults[indexPath.row]
        } else {
            return peers[indexPath.section][indexPath.row]
        }
    }
    
    private func reloadData() {
        let content = self.content
        DispatchQueue.global().async {
            let titles: [String]
            let peers: [[Peer]]
            let contacts = UserDAO.shared.contacts()
            switch content {
            case .chatsAndContacts:
                let conversations = ConversationDAO.shared.conversationList()
                titles = [Localized.CHAT_FORWARD_CHATS,
                          Localized.CHAT_FORWARD_CONTACTS]
                peers = [conversations.compactMap(Peer.init),
                         contacts.map(Peer.init)]
            case .contacts:
                titles = []
                peers = [contacts.map(Peer.init)]
            case .transferReceivers:
                titles = [Localized.CHAT_FORWARD_CHATS,
                          Localized.CHAT_FORWARD_CONTACTS]
                let conversations = ConversationDAO.shared.conversationList()
                let transferAcceptableContacts = contacts.filter({ (user) -> Bool in
                    if user.isBot {
                        return user.appCreatorId == AccountAPI.shared.accountUserId
                    } else {
                        return true
                    }
                })
                let transferAcceptableConversations = conversations.filter({ (conversation) -> Bool in
                    return conversation.category == ConversationCategory.CONTACT.rawValue
                        && !conversation.ownerIsBot
                })
                peers = [transferAcceptableConversations.compactMap(Peer.init),
                         transferAcceptableContacts.map(Peer.init)]
            case .catalogedContacts:
                (titles, peers) = PeerSelectionViewController.catalogedPeers(from: contacts)
            }
            DispatchQueue.main.async { [weak self] in
                guard let weakSelf = self else {
                    return
                }
                weakSelf.headerTitles = titles
                weakSelf.peers = peers
                weakSelf.tableView.reloadData()
            }
        }
    }
    
    private func reloadSelections() {
        tableView.indexPathsForSelectedRows?.forEach({ (indexPath) in
            tableView.deselectRow(at: indexPath, animated: true)
        })
        if isSearching {
            for (row, peer) in searchResults.enumerated() where selections.contains(peer) {
                let indexPath = IndexPath(row: row, section: 0)
                tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
            }
        } else {
            for (section, peers) in peers.enumerated() {
                for (row, peer) in peers.enumerated() where selections.contains(peer) {
                    let indexPath = IndexPath(row: row, section: section)
                    tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
                }
            }
        }
    }
    
}
