import UIKit
import MixinServices

class CirclesViewController: UIViewController {
    
    @IBOutlet weak var toggleCirclesButton: UIButton!
    @IBOutlet weak var tableBackgroundView: UIView!
    @IBOutlet weak var tableView: UITableView!
    
    @IBOutlet weak var showTableViewConstraint: NSLayoutConstraint!
    @IBOutlet weak var hideTableViewConstraint: NSLayoutConstraint!
    
    private lazy var tableFooterView: CirclesTableFooterView = {
        let view = R.nib.circlesTableFooterView(owner: nil)!
        view.button.snp.makeConstraints { (make) in
            make.top.equalTo(view.contentView.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
        return view
    }()
    private lazy var deleteAction = {
        UITableViewRowAction(style: .destructive,
                             title: Localized.MENU_DELETE,
                             handler: tableViewCommitDeleteAction(action:indexPath:))
    }()
    private lazy var editAction: UITableViewRowAction = {
        let action = UITableViewRowAction(style: .normal,
                                          title: R.string.localizable.menu_edit(),
                                          handler: tableViewCommitEditAction(action:indexPath:))
        action.backgroundColor = .theme
        return action
    }()
    private lazy var editNameController = EditNameController(presentingViewController: self)
    
    private var embeddedCircles = CircleDAO.shared.embeddedCircles()
    private var userCircles: [CircleItem] = []
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let tableHeaderView = InfiniteTopView()
        tableHeaderView.frame.size.height = 0
        tableView.tableHeaderView = tableHeaderView
        tableView.register(R.nib.circleCell)
        tableView.dataSource = self
        tableView.delegate = self
        DispatchQueue.global().async {
            self.reloadUserCirclesFromLocalStorage(completion: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(reloadUserCircle), name: CircleDAO.circleDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadUserCircle), name: CircleConversationDAO.circleConversationsDidChangeNotification, object: nil)
    }
    
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if let parent = parent as? HomeViewController {
            let action = #selector(HomeViewController.toggleCircles(_:))
            tableFooterView.button.addTarget(parent, action: action, for: .touchUpInside)
            toggleCirclesButton.addTarget(parent, action: action, for: .touchUpInside)
        }
    }
    
    @IBAction func newCircleAction(_ sender: Any) {
        let addCircle = R.string.localizable.circle_action_add()
        let add = R.string.localizable.action_add()
        editNameController.present(title: addCircle, actionTitle: add, currentName: nil) { (alert) in
            guard let name = alert.textFields?.first?.text else {
                return
            }
            let vc = CircleEditorViewController.instance(name: name, intent: .create)
            self.present(vc, animated: true, completion: nil)
        }
    }
    
    @objc func reloadUserCircle() {
        DispatchQueue.global().async {
            self.reloadUserCirclesFromLocalStorage(completion: nil)
        }
    }
    
    func setTableViewVisible(_ visible: Bool, animated: Bool, completion: (() -> Void)?) {
        if visible {
            reloadUserCircleFromRemote()
            showTableViewConstraint.priority = .defaultHigh
            hideTableViewConstraint.priority = .defaultLow
        } else {
            showTableViewConstraint.priority = .defaultLow
            hideTableViewConstraint.priority = .defaultHigh
        }
        let work = {
            self.view.layoutIfNeeded()
            self.tableBackgroundView.alpha = visible ? 1 : 0
        }
        if animated {
            UIView.animate(withDuration: 0.3, animations: work) { (_) in
                completion?()
            }
        } else {
            work()
            completion?()
        }
    }
    
}

extension CirclesViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let section = Section(rawValue: section)!
        switch section {
        case .embedded:
            return embeddedCircles.count
        case .user:
            return userCircles.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: R.reuseIdentifier.circle, for: indexPath)!
        let section = Section(rawValue: indexPath.section)!
        switch section {
        case .embedded:
            let circle = embeddedCircles[indexPath.row]
            cell.titleLabel.text = "Mixin"
            cell.subtitleLabel.text = R.string.localizable.circle_conversation_count_all()
            cell.unreadCount = circle.unreadCount
        case .user:
            let circle = userCircles[indexPath.row]
            cell.titleLabel.text = circle.name
            cell.subtitleLabel.text = R.string.localizable.circle_conversation_count("\(circle.conversationCount)")
            cell.unreadCount = circle.unreadCount
        }
        return cell
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }
    
}

extension CirclesViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == Section.user.rawValue
    }
    
    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        [deleteAction, editAction]
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let section = Section(rawValue: indexPath.section)!
        switch section {
        case .embedded:
            AppGroupUserDefaults.User.circleId = nil
        case .user:
            let circle = userCircles[indexPath.row]
            AppGroupUserDefaults.User.circleId = circle.circleId
        }
        UIApplication.homeViewController?.setNeedsRefresh()
    }
    
}

extension CirclesViewController {
    
    private enum Section: Int, CaseIterable {
        case embedded = 0
        case user
    }
    
    private func tableViewCommitEditAction(action: UITableViewRowAction, indexPath: IndexPath) {
        let circle = userCircles[indexPath.row]
        let editName = R.string.localizable.circle_action_edit_name()
        let change = R.string.localizable.dialog_button_change()
        let editConversation = R.string.localizable.circle_action_edit_conversations()
        let cancel = R.string.localizable.dialog_button_cancel()
        
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: editName, style: .default, handler: { (_) in
            self.editNameController.present(title: editName, actionTitle: change, currentName: circle.name) { (alert) in
                guard let name = alert.textFields?.first?.text else {
                    return
                }
                self.editCircle(with: circle.circleId, name: name)
            }
        }))
        sheet.addAction(UIAlertAction(title: editConversation, style: .default, handler: { (_) in
            let vc = CircleEditorViewController.instance(name: circle.name, intent: .update(id: circle.circleId))
            self.present(vc, animated: true, completion: nil)
        }))
        sheet.addAction(UIAlertAction(title: cancel, style: .cancel, handler: nil))
        
        present(sheet, animated: true, completion: nil)
    }
    
    private func tableViewCommitDeleteAction(action: UITableViewRowAction, indexPath: IndexPath) {
        let circle = userCircles[indexPath.row]
        let delete = R.string.localizable.circle_action_delete()
        let cancel = R.string.localizable.dialog_button_cancel()
        let sheet = UIAlertController(title: circle.name, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: delete, style: .destructive, handler: { (_) in
            let hud = Hud()
            hud.show(style: .busy, text: "", on: AppDelegate.current.window)
            CircleAPI.shared.delete(id: circle.circleId) { (result) in
                switch result {
                case .success:
                    DispatchQueue.global().async {
                        CircleDAO.shared.delete(circleId: circle.circleId)
                        CircleConversationDAO.shared.delete(circleId: circle.circleId)
                        self.reloadUserCirclesFromLocalStorage {
                            hud.set(style: .notification, text: R.string.localizable.toast_deleted())
                        }
                    }
                case .failure(let error):
                    hud.set(style: .error, text: error.localizedDescription)
                }
                hud.scheduleAutoHidden()
            }
        }))
        sheet.addAction(UIAlertAction(title: cancel, style: .cancel, handler: nil))
        present(sheet, animated: true, completion: nil)
    }
    
    private func editCircle(with circleId: String, name: String) {
        let hud = Hud()
        hud.show(style: .busy, text: "", on: AppDelegate.current.window)
        CircleAPI.shared.update(id: circleId, name: name, completion: { result in
            switch result {
            case .success(let circle):
                DispatchQueue.global().async {
                    CircleDAO.shared.insertOrReplace(circle: circle)
                    self.reloadUserCirclesFromLocalStorage() {
                        hud.set(style: .notification, text: R.string.localizable.toast_saved())
                    }
                }
            case .failure(let error):
                hud.set(style: .error, text: error.localizedDescription)
            }
            hud.scheduleAutoHidden()
        })
    }
    
    private func reloadUserCircleFromRemote() {
        CircleAPI.shared.circles { [weak self] (result) in
            guard case let .success(circles) = result else {
                return
            }
            DispatchQueue.global().async {
                CircleDAO.shared.insertOrReplace(circles: circles)
                self?.reloadUserCirclesFromLocalStorage(completion: nil)
            }
        }
    }
    
    private func reloadUserCirclesFromLocalStorage(completion: (() -> Void)?) {
        let circles = CircleDAO.shared.circles()
        DispatchQueue.main.sync {
            self.userCircles = circles
            self.tableView.reloadData()
            self.tableFooterView.showsHintLabel = circles.isEmpty
            self.tableView.tableFooterView = self.tableFooterView
            self.tableView.layoutIfNeeded()
            let cellsHeight = CGFloat(circles.count + 1) * self.tableView.rowHeight
            let height = max(self.tableFooterView.contentView.frame.height,
                             self.tableView.frame.height - cellsHeight)
            self.tableFooterView.frame.size.height = height
            self.tableView.tableFooterView = self.tableFooterView
            let indexPath: IndexPath
            if let circleId = AppGroupUserDefaults.User.circleId, let row = circles.firstIndex(where: { $0.circleId == circleId }) {
                indexPath = IndexPath(row: row, section: 1)
            } else {
                indexPath = IndexPath(row: 0, section: 0)
            }
            self.tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            completion?()
        }
    }
    
}