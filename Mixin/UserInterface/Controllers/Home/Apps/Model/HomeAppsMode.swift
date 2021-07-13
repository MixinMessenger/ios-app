import Foundation

enum HomeAppsMode {
    
    case regular
    case pinned
    case folder
    case nestedFolder
    
    static let nestedFolderSize = CGSize(width: 60, height: 60)
    static let folderRemovalInterval: TimeInterval = 0.5
    static let folderInterval: TimeInterval = 0.7
    static let pageInterval: TimeInterval = 0.7
    
    var sectionInset: UIEdgeInsets {
        switch self {
        case .regular:
            return UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        case .pinned:
            return UIEdgeInsets(top: 11, left: 16, bottom: 11, right: 16)
        case .folder:
            return UIEdgeInsets(top: 12, left: 30, bottom: 12, right: 30)
        case .nestedFolder:
            return UIEdgeInsets(top: 7, left: 7, bottom: 7, right: 7)
        }
    }
    
    var minimumInteritemSpacing: CGFloat {
        var margin: CGFloat = 0
        var totalWidth = AppDelegate.current.mainWindow.bounds.width
        switch self {
        case .regular:
            margin = 0
        case .pinned:
            margin = 20
        case .folder:
            margin = 32
        case .nestedFolder:
            margin = 0
            totalWidth = 60
        }
        let cellsWidth = itemSize.width * CGFloat(appsPerRow)
        let totalSpacing = totalWidth - margin * 2 - sectionInset.horizontal - cellsWidth
        return floor(totalSpacing / CGFloat(appsPerRow - 1))
    }
    
    var minimumLineSpacing: CGFloat {
        switch self {
        case .nestedFolder:
            return 2
        default:
            return 0
        }
    }
    
    var itemSize: CGSize {
        switch self {
        case .regular:
            return CGSize(width: 80, height: 100)
        case .pinned:
            return CGSize(width: 60, height: 60)
        case .folder:
            return CGSize(width: 80, height: 100)
        case .nestedFolder:
            return CGSize(width: 14, height: 14)
        }
    }
    
    var pageSize: CGSize {
        let screenWidth = AppDelegate.current.mainWindow.bounds.width
        switch self {
        case .regular:
            return CGSize(width: screenWidth, height: itemSize.height * CGFloat(rowsPerPage))
        case .pinned:
            return CGSize(width: screenWidth - 20 * 2, height: 82)
        case .folder:
            return CGSize(width: screenWidth - 32 * 2, height: 328)
        case .nestedFolder:
            return CGSize(width: 60, height: 60)
        }
    }
    
    var appsPerRow: Int {
        switch self {
        case .regular:
            return 4
        case .pinned:
            return 4
        case .folder:
            return 3
        case .nestedFolder:
            return 3
        }
    }
    
    var rowsPerPage: Int {
        switch self {
        case .regular:
            return (ScreenHeight.current == .medium ? 3 : 4)
        case .pinned:
            return 1
        case .folder:
            return 3
        case .nestedFolder:
            return 3
        }
    }
    
    var appsPerPage: Int {
        return rowsPerPage * appsPerRow
    }
    
}
