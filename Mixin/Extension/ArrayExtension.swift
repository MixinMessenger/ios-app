import Foundation

extension Array {

    mutating func add(element: Array.Element) -> Array<Element> {
        self.append(element)
        return self
    }

    public func indexSearchingBackwards(where predicate: (Element) throws -> Bool) rethrows -> Int? {
        guard let reversedIndex = try reversed().index(where: predicate) else {
            return nil
        }
        return index(before: reversedIndex.base)
    }
    
    func safeIndex(before i: Int) -> Int? {
        let index = self.index(before: i)
        return index >= self.startIndex ? index : nil
    }
    
    func safeIndex(after i: Int) -> Int? {
        let index = self.index(after: i)
        return index < self.endIndex ? index : nil
    }


}

extension Array where Iterator.Element: Hashable {

    func distinct() -> [Iterator.Element] {
        return Array(Set(self))
    }
}

extension Array where Iterator.Element: Equatable {
    
    func element(before element: Element) -> Element? {
        guard let index = index(of: element), let indexBefore = self.safeIndex(before: index) else {
            return nil
        }
        return self[indexBefore]
    }
    
    func element(after element: Element) -> Element? {
        guard let index = index(of: element) else {
            return nil
        }
        var possibleIndexAfter = self.safeIndex(after: index)
        while let idx = possibleIndexAfter, self[idx] == element {
            possibleIndexAfter = self.safeIndex(after: idx)
        }
        guard let indexAfter = possibleIndexAfter else {
            return nil
        }
        return self[indexAfter]
    }
    
}
