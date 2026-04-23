import Foundation

enum ClipboardEnqueueResult: Equatable {
    case queued(count: Int)
    case empty
    case duplicate
}

final class ClipboardQueue {
    private var messages: [String] = []

    var count: Int {
        messages.count
    }

    var isEmpty: Bool {
        messages.isEmpty
    }

    func enqueue(_ text: String) -> ClipboardEnqueueResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty
        }

        guard messages.last != text else {
            return .duplicate
        }

        messages.append(text)
        return .queued(count: messages.count)
    }

    func dequeue() -> String? {
        guard !messages.isEmpty else {
            return nil
        }

        return messages.removeFirst()
    }

    func putBackAtFront(_ text: String) {
        messages.insert(text, at: 0)
    }

    func clear() {
        messages.removeAll()
    }

    func remove(at index: Int) {
        guard messages.indices.contains(index) else {
            return
        }

        messages.remove(at: index)
    }

    func allMessages() -> [String] {
        messages
    }

    func nextPreview(limit: Int = 72) -> String? {
        guard let next = messages.first else {
            return nil
        }

        return Self.preview(next, limit: limit)
    }

    func previews(limit: Int = 64, maxItems: Int = 5) -> [String] {
        messages
            .prefix(maxItems)
            .enumerated()
            .map { index, message in
                "\(index + 1). \(Self.preview(message, limit: limit))"
            }
    }

    static func preview(_ text: String, limit: Int = 72) -> String {
        let collapsedWhitespace = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard collapsedWhitespace.count > limit else {
            return collapsedWhitespace
        }

        let endIndex = collapsedWhitespace.index(collapsedWhitespace.startIndex, offsetBy: limit)
        return String(collapsedWhitespace[..<endIndex]) + "..."
    }
}
