import Foundation

extension CGAffineTransform {
    
    static func transform(rect fromRect: CGRect, to toRect: CGRect) -> CGAffineTransform {
        
        let scaleWidth = toRect.width / fromRect.width
        let scaleHeight = toRect.height / fromRect.height
        let transform = CGAffineTransform.identity.translatedBy(x: toRect.midX - fromRect.midX, y: toRect.midY - fromRect.midY)
        return transform.scaledBy(x: scaleWidth, y: scaleHeight)
    }
    
}

extension Array {
    
    mutating func remove(at indexes: [Int]) {
        var lastIndex: Int? = nil
        for index in indexes.sorted(by: >) {
            guard lastIndex != index else {
                continue
            }
            remove(at: index)
            lastIndex = index
        }
    }
    
    func splitInPages(ofSize size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, self.count)])
        }
    }
    
}
