import AppKit
import SwiftUI

/// A single-line AppKit text field that takes focus as soon as it appears. Return calls `onSubmit`,
/// Esc calls `onCancel`. AppKit-backed because SwiftUI's @FocusState, like @State, needs the macro
/// plugin that ships only with full Xcode.
struct FocusedTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    /// Rounded-border field (forms) or bare text (inside the search capsule).
    var bordered = false
    var onSubmit: () -> Void = {}
    var onCancel: () -> Void = {}

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.isBezeled = bordered
        field.bezelStyle = .roundedBezel
        field.isBordered = bordered
        field.drawsBackground = bordered
        field.focusRingType = bordered ? .default : .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.delegate = context.coordinator
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusedTextField
        init(parent: FocusedTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel()
            default: return false
            }
            return true
        }
    }
}
