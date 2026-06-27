//
//  MessageComposeView.swift
//  PourChoices
//
//  UIViewControllerRepresentable that wraps MFMessageComposeViewController
//  for sending pre-filled invite texts.
//

import SwiftUI
import MessageUI

struct MessageComposeView: UIViewControllerRepresentable {
    let recipients: [String]?
    let messageBody: String
    var onDismiss: () -> Void

    static var canSendText: Bool { MFMessageComposeViewController.canSendText() }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = recipients
        vc.body = messageBody
        vc.messageComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true)
            onDismiss()
        }
    }
}
