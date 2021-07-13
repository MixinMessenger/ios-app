import Foundation
import MixinServices

class HomeAppsItemManager {
    
    typealias JSONDictionary = [String: Any]
    typealias JSONArray = [JSONDictionary]
    
    private(set) var candidateItems: [[AppItem]] = []
    private(set) var pinnedItems: [AppItem] = []
    private var existsItemIds: Set<String> = []
    
    init() {
        if let jsonData = AppGroupUserDefaults.User.homeAppsFolder {
            setupItems(with: jsonData)
        } else {
            initItems()
            saveItems()
        }
    }
    
    func updateItems(_ pinnedItems: [AppItem], _ candidateItems: [[AppItem]]) {
        self.pinnedItems = pinnedItems
        self.candidateItems = candidateItems
        saveItems()
    }
    
}

extension HomeAppsItemManager {
    
    private func initItems() {
        let pinnedIds = Set(AppGroupUserDefaults.User.homeAppIds)
        pinnedItems = pinnedIds.compactMap({ return AppModel(id: $0) })
        var candidateEmbeddedApps = EmbeddedApp.all
        candidateEmbeddedApps.removeAll(where: {
            pinnedIds.contains($0.id)
        })
        let appUsers = UserDAO.shared.getAppUsers()
        let candidateAppUsers = appUsers.filter { (user) -> Bool in
            if let id = user.appId {
                return !pinnedIds.contains(id)
            } else {
                return false
            }
        }
        candidateItems = {
            let itemIds = candidateEmbeddedApps.map({ $0.id }) + candidateAppUsers.compactMap({ $0.appId })
            let items = itemIds.map({ AppModel(id: $0) })
            return items.splitInPages(ofSize: HomeAppsMode.regular.appsPerPage)
        }()
    }
    
    private func setupItems(with jsonData: Data) {
        existsItemIds.removeAll()
        let embeddedAppIds = EmbeddedApp.all.map({ $0.id })
        let appUserIds = UserDAO.shared.getAppUsers().compactMap({ $0.appId })
        let allAppIds = embeddedAppIds + appUserIds
        do {
            if let parsedDict = try JSONSerialization.jsonObject(with: jsonData, options: []) as? JSONDictionary,
               let pinnedJSONArray = parsedDict["pinned"] as? JSONArray,
               let pagesJSONArray = parsedDict["pages"] as? [JSONArray] {
                pinnedItems = appItems(from: pinnedJSONArray, allAppIds: allAppIds)
                candidateItems = pagesJSONArray.compactMap({ jsonArray -> [AppItem]? in
                    let page = appItems(from: jsonArray, allAppIds: allAppIds)
                    return page.count > 0 ? page : nil
                })
                // apped newly added apps
                let newlyAddedItemIds = Set(allAppIds).subtracting(existsItemIds)
                if newlyAddedItemIds.count > 0 {
                    let newlyAddedItems = newlyAddedItemIds.map( { AppModel(id: $0) })
                    let newlyAddedItemPages = newlyAddedItems.splitInPages(ofSize: HomeAppsMode.regular.appsPerPage)
                    candidateItems += newlyAddedItemPages
                }
            } else {
                initItems()
            }
        } catch {
            initItems()
        }
    }
    
    private func appItems(from jsonArray: JSONArray, allAppIds: [String]) -> [AppItem] {
        return jsonArray.compactMap { item -> AppItem? in
            guard let typeID = item["type"] as? Int, let type = HomeAppItemType(rawValue: typeID) else {
                return nil
            }
            switch type {
            case .app:
                guard let id = item["id"] as? String, allAppIds.contains(id), !existsItemIds.contains(id) else {
                    return nil
                }
                existsItemIds.insert(id)
                return AppModel(id: id)
            case .folder:
                guard let name = item["name"] as? String, let apps = item["apps"] as? [[JSONDictionary]] else {
                    return nil
                }
                let pages = apps.compactMap { pageItems -> [AppModel]? in
                    let page = pageItems.compactMap { item -> AppModel? in
                        guard let id = item["id"] as? String, allAppIds.contains(id), !existsItemIds.contains(id) else {
                            return nil
                        }
                        existsItemIds.insert(id)
                        return AppModel(id: id)
                    }
                    return page.count > 0 ? page : nil
                }
                return pages.count > 0 ? AppFolderModel(name: name, pages: pages) : nil
            }
        }
    }
    
    private func saveItems() {
        DispatchQueue.global().async {
            let pinnedItems = self.pinnedItems.map { $0.toDictionary() }
            let pages = self.candidateItems.map { page -> [JSONDictionary] in
                return page.map { $0.toDictionary() }
            }
            let dictionary = ["pages": pages, "pinned": pinnedItems] as JSONDictionary
            let jsonData = try! JSONSerialization.data(withJSONObject: dictionary, options: [])
            AppGroupUserDefaults.User.homeAppsFolder = jsonData
            AppGroupUserDefaults.User.homeAppIds = self.pinnedItems.compactMap({ ($0 as? AppModel)?.id })
        }
    }
    
}
