// The bridge reports "nothing" as empty strings; these turn them into nil.

extension String {
    /// The string, or nil if it's empty. The bridge reports "none" as an empty string.
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// The same, for optional strings.
extension Optional where Wrapped == String {
    /// The string, unless it's nil or empty.
    var nonEmpty: String? { self?.nonEmpty }
}
