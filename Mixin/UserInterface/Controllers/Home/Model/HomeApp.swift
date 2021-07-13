import Foundation
import MixinServices

enum HomeApp {
    
    case embedded(EmbeddedApp)
    case external(User)
    
    var id: String {
        switch self {
        case .embedded(let app):
            return app.id
        case .external(let user):
            assert(user.appId != nil)
            return user.appId ?? ""
        }
    }
    
    init?(id: String) {
        if let app = EmbeddedApp.all.first(where: { $0.id == id }) {
            self = .embedded(app)
        } else if var user = UserDAO.shared.getFriendUser(withAppId: id) {
            user.app = AppDAO.shared.getApp(appId: id)
            self = .external(user)
        } else {
            return nil
        }
    }

    var categoryIcon: UIImage? {
        switch self {
        case .embedded(let app):
            return app.categoryIcon
        case .external(let user):
            switch user.app?.category ?? AppCategory.OTHER.rawValue {
            case AppCategory.WALLET.rawValue:
                return R.image.ic_app_category_wallet()
            case AppCategory.TRADING.rawValue:
                return R.image.ic_app_category_trading()
            case AppCategory.BUSINESS.rawValue:
                return R.image.ic_app_category_business()
            case AppCategory.SOCIAL.rawValue:
                return R.image.ic_app_category_social()
            case AppCategory.SHOPPING.rawValue:
                return R.image.ic_app_category_shopping()
            case AppCategory.EDUCATION.rawValue:
                return R.image.ic_app_category_education()
            case AppCategory.NEWS.rawValue:
                return R.image.ic_app_category_news()
            case AppCategory.TOOLS.rawValue:
                return R.image.ic_app_category_tools()
            case AppCategory.GAMES.rawValue:
                return R.image.ic_app_category_game()
            case AppCategory.BOOKS.rawValue:
                return R.image.ic_app_category_book()
            case AppCategory.MUSIC.rawValue:
                return R.image.ic_app_category_music()
            case AppCategory.PHOTO.rawValue:
                return R.image.ic_app_category_photo()
            case AppCategory.VIDEO.rawValue:
                return R.image.ic_app_category_video()
            default:
                return R.image.ic_app_category_other()
            }
        }
    }
    
    var category: String {
        switch self {
        case .embedded(let app):
            switch app.name {
            case R.string.localizable.scan_qr_code():
                return R.string.localizable.app_category_tools()
            case R.string.localizable.action_camera():
                return R.string.localizable.app_category_camera()
            case R.string.localizable.wallet_title():
                return R.string.localizable.app_category_wallet()
            default:
                return R.string.localizable.app_category_other()
            }
        case .external(let user):
            switch user.app?.category ?? AppCategory.OTHER.rawValue {
            case AppCategory.WALLET.rawValue:
                return R.string.localizable.app_category_wallet()
            case AppCategory.TRADING.rawValue:
                return R.string.localizable.app_category_trading()
            case AppCategory.BUSINESS.rawValue:
                return R.string.localizable.app_category_business()
            case AppCategory.SOCIAL.rawValue:
                return R.string.localizable.app_category_social()
            case AppCategory.SHOPPING.rawValue:
                return R.string.localizable.app_category_shopping()
            case AppCategory.EDUCATION.rawValue:
                return R.string.localizable.app_category_education()
            case AppCategory.NEWS.rawValue:
                return R.string.localizable.app_category_news()
            case AppCategory.TOOLS.rawValue:
                return R.string.localizable.app_category_tools()
            case AppCategory.GAMES.rawValue:
                return R.string.localizable.app_category_games()
            case AppCategory.BOOKS.rawValue:
                return R.string.localizable.app_category_books()
            case AppCategory.MUSIC.rawValue:
                return R.string.localizable.app_category_music()
            case AppCategory.PHOTO.rawValue:
                return R.string.localizable.app_category_photo()
            case AppCategory.VIDEO.rawValue:
                return R.string.localizable.app_category_video()
            default:
                return R.string.localizable.app_category_other()
            }
        }
    }
    
}

extension HomeApp: Equatable {
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
    
}
