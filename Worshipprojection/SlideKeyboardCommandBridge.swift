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
        return controller
    }

    func updateUIViewController(_ controller: KeyboardCommandViewController, context: Context) {
        controller.onPrevious = goPrevious
        controller.onNext = goNext
        controller.canGoPrevious = canGoPrevious
        controller.canGoNext = canGoNext
        DispatchQueue.main.async {
            controller.refreshFirstResponder()
        }
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
        becomeFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !isFirstResponder {
            becomeFirstResponder()
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(previousSlide)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(previousSlide)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(nextSlide)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(nextSlide))
        ]
    }

    func refreshFirstResponder() {
        guard view.window != nil, !isFirstResponder else { return }
        becomeFirstResponder()
    }

    @objc private func previousSlide() {
        guard canGoPrevious else { return }
        onPrevious?()
    }

    @objc private func nextSlide() {
        guard canGoNext else { return }
        onNext?()
    }
}
