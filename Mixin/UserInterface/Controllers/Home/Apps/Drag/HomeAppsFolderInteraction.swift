import Foundation

protocol HomeAppsFolderInteraction {
    
    var dragInteraction: HomeAppsDragInteraction { get set }
    var item: AppItem { get set }
    var isDismissing: Bool { get set }
    var wrapperView: UIView { get set }
    
}

class HomeAppsFolderCreationInteraction: HomeAppsFolderInteraction {
    
    var dragInteraction: HomeAppsDragInteraction
    var destinationApp: AppModel
    var wrapperView: UIView
    var isDismissing: Bool = false
    
    var item: AppItem
    
    required init(dragInteraction: HomeAppsDragInteraction, destinationApp: AppModel, wrapperView: UIView) {
        self.dragInteraction = dragInteraction
        self.destinationApp = destinationApp
        self.item = destinationApp
        self.wrapperView = wrapperView
    }
    
}

class HomeAppsFolderDropInteraction: HomeAppsFolderInteraction {
    
    var dragInteraction: HomeAppsDragInteraction
    var folder: AppFolderModel
    var wrapperView: UIView
    var isDismissing: Bool = false
    
    var item: AppItem
    
    required init(dragInteraction: HomeAppsDragInteraction, folder: AppFolderModel, wrapperView: UIView) {
        self.dragInteraction = dragInteraction
        self.folder = folder
        self.item = folder
        self.wrapperView = wrapperView
    }
    
}

class HomeAppsOpenFolderInfo {
    
    var folder: AppFolderModel
    var cell: AppFolderCell
    var isNewFolder: Bool
    var shouldCancelCreation = false
    
    required init(cell: AppFolderCell, isNewFolder: Bool) {
        self.cell = cell
        self.folder = cell.item as! AppFolderModel
        self.isNewFolder = isNewFolder
    }
    
}
