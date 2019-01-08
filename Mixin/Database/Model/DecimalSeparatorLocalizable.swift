
func decimalSeparatorLocalized(_ str: String) -> String {
    if let decimalSeparator = Locale.current.decimalSeparator, decimalSeparator != "." {
        return str.replacingOccurrences(of: ".", with: decimalSeparator)
    } else {
        return str
    }
}
