import ApplicationServices
import Foundation

enum TypingResult: Equatable {
    case completed
    case cancelled
    case failed(String)
}

enum TypingSpeed {
    static let minimumWordsPerMinute = 100.0
    static let maximumWordsPerMinute = 500.0
    static let defaultWordsPerMinute = 160.0

    static func clamped(_ value: Double) -> Double {
        min(max(value, minimumWordsPerMinute), maximumWordsPerMinute)
    }

    static func savedValue(_ value: Double?) -> Double {
        guard let value, value > 0 else {
            return defaultWordsPerMinute
        }

        return clamped(value)
    }
}

final class Typer {
    private let lock = NSLock()
    private var activeWorkItem: DispatchWorkItem?
    private var cancelRequested = false
    private var selectedWordsPerMinute: Double

    init(wordsPerMinute: Double = TypingSpeed.defaultWordsPerMinute) {
        selectedWordsPerMinute = TypingSpeed.clamped(wordsPerMinute)
    }

    var isTyping: Bool {
        withLock {
            activeWorkItem != nil
        }
    }

    var wordsPerMinute: Double {
        get {
            withLock {
                selectedWordsPerMinute
            }
        }
        set {
            withLock {
                selectedWordsPerMinute = TypingSpeed.clamped(newValue)
            }
        }
    }

    func startTyping(_ text: String, completion: @escaping (TypingResult) -> Void) -> Bool {
        let wordsPerMinute = self.wordsPerMinute

        guard withLock({
            guard activeWorkItem == nil else {
                return false
            }

            cancelRequested = false
            return true
        }) else {
            return false
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            let result = self.typeText(text, wordsPerMinute: wordsPerMinute)

            DispatchQueue.main.async {
                self.finish()
                completion(result)
            }
        }

        withLock {
            activeWorkItem = workItem
        }

        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
        return true
    }

    func cancel() {
        withLock {
            cancelRequested = true
            activeWorkItem?.cancel()
        }
    }

    private func typeText(_ text: String, wordsPerMinute: Double) -> TypingResult {
        guard !text.isEmpty else {
            return .completed
        }

        let source = CGEventSource(stateID: .hidSystemState)

        for character in text {
            if isCancellationRequested {
                return .cancelled
            }

            guard post(character: character, source: source) else {
                return .failed("Could not create keyboard events for typing.")
            }

            if isCancellationRequested {
                return .cancelled
            }

            Thread.sleep(forTimeInterval: delay(after: character, wordsPerMinute: wordsPerMinute))
        }

        return .completed
    }

    private func post(character: Character, source: CGEventSource?) -> Bool {
        let text = String(character)
        let unicode = Array(text.utf16)

        guard !unicode.isEmpty,
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else {
            return false
        }

        unicode.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
            keyUp.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }

        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: Double.random(in: 0.004...0.012))
        keyUp.post(tap: .cghidEventTap)

        return true
    }

    private func delay(after character: Character, wordsPerMinute: Double) -> TimeInterval {
        let wpm = TypingSpeed.clamped(wordsPerMinute * Double.random(in: 0.92...1.08))
        let averageCharacterDelay = 60.0 / (wpm * 5.0)
        var delay = averageCharacterDelay * Double.random(in: 0.55...1.35)

        let text = String(character)

        if text.rangeOfCharacter(from: .newlines) != nil {
            delay += Double.random(in: 0.35...0.65)
        } else if text.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?")) != nil {
            delay += Double.random(in: 0.22...0.42)
        } else if text.rangeOfCharacter(from: CharacterSet(charactersIn: ",;:")) != nil {
            delay += Double.random(in: 0.10...0.24)
        } else if text.rangeOfCharacter(from: .whitespaces) != nil {
            delay *= Double.random(in: 0.55...0.80)
        }

        return max(0.015, delay)
    }

    private var isCancellationRequested: Bool {
        withLock {
            cancelRequested || activeWorkItem?.isCancelled == true
        }
    }

    private func finish() {
        withLock {
            activeWorkItem = nil
            cancelRequested = false
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer {
            lock.unlock()
        }
        return body()
    }
}
