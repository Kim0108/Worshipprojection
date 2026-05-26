import SwiftUI
import UIKit

struct SlideKeyboardCommandBridge: UIViewControllerRepresentable {
    var canGoPrevious: Bool
    var canGoNext: Bool
    var goPrevious: () -> Void
    var goNext: () -> Void

    func makeUIViewController(context: Context) -> KeyboardCommandViewController {
        let controller = KeyboardCommandViewController()
        controller.view.backgroundColor = .clear
        controller.onPrevious = goPrevious
        controller.onNext = goNext
        controller.canGoPrevious = canGoPrevious
        controller.canGoNext = canGoNext
        DispatchQueue.main.async {
            controller.activateKeyboardCommandsIfAvailable()
        }
        return controller
    }

    func updateUIViewController(_ controller: KeyboardCommandViewController, context: Context) {
        controller.onPrevious = goPrevious
        controller.onNext = goNext
        controller.canGoPrevious = canGoPrevious
        controller.canGoNext = canGoNext
    }
}

final class KeyboardCommandViewController: UIViewController {
    var canGoPrevious = false
    var canGoNext = false
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        activateKeyboardCommandsIfAvailable()
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            keyCommand(input: UIKeyCommand.inputLeftArrow, action: #selector(previousSlide), title: "上一張"),
            keyCommand(input: UIKeyCommand.inputUpArrow, action: #selector(previousSlide), title: "上一張"),
            keyCommand(input: UIKeyCommand.inputRightArrow, action: #selector(nextSlide), title: "下一張"),
            keyCommand(input: UIKeyCommand.inputDownArrow, action: #selector(nextSlide), title: "下一張")
        ]
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard !Self.textInputIsActive else {
            super.pressesBegan(presses, with: event)
            return
        }

        let handled = presses.contains { press in
            switch press.type {
            case .leftArrow, .upArrow:
                previousSlide()
                return true
            case .rightArrow, .downArrow:
                nextSlide()
                return true
            default:
                return false
            }
        }

        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    func activateKeyboardCommandsIfAvailable() {
        guard view.window != nil, !isFirstResponder, !Self.textInputIsActive else { return }
        becomeFirstResponder()
    }

    private func keyCommand(input: String, action: Selector, title: String) -> UIKeyCommand {
        let command = UIKeyCommand(input: input, modifierFlags: [], action: action, discoverabilityTitle: title)
        command.wantsPriorityOverSystemBehavior = true
        return command
    }

    @objc private func previousSlide() {
        guard !Self.textInputIsActive else { return }
        guard canGoPrevious else { return }
        onPrevious?()
    }

    @objc private func nextSlide() {
        guard !Self.textInputIsActive else { return }
        guard canGoNext else { return }
        onNext?()
    }

    private static var textInputIsActive: Bool {
        UIResponder.currentFirstResponder is any UITextInput
    }
}

private extension UIResponder {
    private weak static var discoveredFirstResponder: UIResponder?

    static var currentFirstResponder: UIResponder? {
        discoveredFirstResponder = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.captureFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        return discoveredFirstResponder
    }

    @objc private func captureFirstResponder() {
        UIResponder.discoveredFirstResponder = self
    }
}
