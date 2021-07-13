import Foundation

class AppModel: AppItem {
    
    var id: String
    var app: HomeApp? {
        return HomeApp(id: id)
    }
    
    init(id: String) {
        self.id = id
    }
    
    func toDictionary() -> [String : Any] {
        return ["type": HomeAppItemType.app.rawValue, "id": id] as [String: Any]
    }
    
}

extension AppModel: Equatable {
    
    static func == (lhs: AppModel, rhs: AppModel) -> Bool {
        return lhs === rhs
    }
    
}
