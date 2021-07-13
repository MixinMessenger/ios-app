import Foundation

class AppFolderModel: AppItem {
    
    var name: String
    var pages: [[AppModel]]
    var isNewFolder = false
    
    init(name: String, pages: [[AppModel]]) {
        self.name = name
        self.pages = pages
    }
    
    func toDictionary() -> [String : Any] {
        let apps = pages.map { page -> [[String : Any]] in
            return page.map { $0.toDictionary() }
        }
        return ["type": HomeAppItemType.folder.rawValue, "name": name, "apps": apps]
    }
    
}

extension AppFolderModel: Equatable {
    
    static func == (lhs: AppFolderModel, rhs: AppFolderModel) -> Bool {
        return lhs === rhs
    }
    
}
