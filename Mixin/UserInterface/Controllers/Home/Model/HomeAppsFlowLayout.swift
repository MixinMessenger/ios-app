import UIKit

class HomeAppsFlowLayout: UICollectionViewFlowLayout {
    
    let lineSpacing: CGFloat
    let interitemSpacing: CGFloat
    let numberOfRows: Int
    let numberOfColumns: Int
    let cellSize: CGSize
    let pageInset: UIEdgeInsets
    
    private var cache: [UICollectionViewLayoutAttributes] = []
    private var contentSize: CGSize = .zero
    
    init(lineSpacing: CGFloat, interitemSpacing: CGFloat, numberOfRows: Int, numberOfColumns: Int, cellSize: CGSize, pageInset: UIEdgeInsets) {
        self.lineSpacing = lineSpacing
        self.interitemSpacing = interitemSpacing
        self.numberOfRows = numberOfRows
        self.numberOfColumns = numberOfColumns
        self.cellSize = cellSize
        self.pageInset = pageInset
        super.init()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var collectionViewContentSize: CGSize {
        contentSize
    }
    
    override func invalidateLayout() {
        super.invalidateLayout()
        cache = []
    }
    
    override func prepare() {
        guard cache.isEmpty, let collectionView = collectionView else {
            return
        }

        assert(collectionView.numberOfSections == 1)
        
        guard collectionView.numberOfItems(inSection: 0) > 0 else {
            return
        }
        let cellWidth = cellSize.width
        let cellHeight = cellSize.height
        let pageWidth = collectionView.bounds.size.width
        for item in 0..<collectionView.numberOfItems(inSection: 0) {
            let pageIndex = item / (numberOfRows * numberOfColumns)
            let rowIndex = (item / numberOfColumns) % numberOfRows
            let columnIndex = item % numberOfColumns
            
            let x = CGFloat(pageIndex) * pageWidth
                + collectionView.contentInset.left
                + pageInset.left
                + CGFloat(columnIndex) * (cellWidth + interitemSpacing)
            let y = collectionView.contentInset.top
                + pageInset.top
                + CGFloat(rowIndex) * (cellHeight + lineSpacing)
            
            let indexPath = IndexPath(item: item, section: 0)
            let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            let frame = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
            attributes.frame = frame
            cache.append(attributes)
            
            contentSize = CGSize(width: pageWidth * CGFloat(pageIndex + 1),
                                 height: max(contentSize.height, frame.maxY))
        }
    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let attributes = cache.filter { (attributes) -> Bool in
            attributes.frame.intersects(rect)
        }
        return attributes
    }
    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        cache[indexPath.item]
    }
    
}
