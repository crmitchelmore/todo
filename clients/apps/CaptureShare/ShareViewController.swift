import UIKit
import UniformTypeIdentifiers
import CaptureCore

/// Fast capture from any app's Share Sheet. Pulls the shared text/URL, lets you tweak it in one
/// field, and ingests it as a `proposed` row via the backend (never touches PowerSync directly).
final class ShareViewController: UIViewController {
    private let textView = UITextView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let ingress = CaptureConfig.fromEnvironment().makeIngress()

    private var sharedURL: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildUI()
        loadSharedItem()
    }

    private func buildUI() {
        navigationItemSetup()

        textView.font = .systemFont(ofSize: 18)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.layer.cornerRadius = 10
        textView.backgroundColor = .secondarySystemBackground
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        view.addSubview(textView)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.heightAnchor.constraint(equalToConstant: 120),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 16)
        ])
    }

    private func navigationItemSetup() {
        let nav = UINavigationBar()
        nav.translatesAutoresizingMaskIntoConstraints = false
        let item = UINavigationItem(title: "Capture")
        item.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        item.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))
        nav.items = [item]
        view.addSubview(nav)
        NSLayoutConstraint.activate([
            nav.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            nav.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            nav.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func loadSharedItem() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments else { return }

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] data, _ in
                    let url = (data as? URL)?.absoluteString
                    DispatchQueue.main.async {
                        self?.sharedURL = url
                        if self?.textView.text.isEmpty ?? true { self?.textView.text = url ?? "" }
                        self?.textView.becomeFirstResponder()
                    }
                }
                return
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] data, _ in
                    let text = data as? String
                    DispatchQueue.main.async {
                        self?.textView.text = text ?? ""
                        self?.textView.becomeFirstResponder()
                    }
                }
                return
            }
        }
        textView.becomeFirstResponder()
    }

    @objc private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "capture", code: 0))
    }

    @objc private func save() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { cancel(); return }
        spinner.startAnimating()
        let input = CaptureInput(rawText: text, url: sharedURL, source: "share-extension")
        Task {
            try? await ingress.capture(input) // resilient: backend, else App Group outbox
            await MainActor.run {
                self.spinner.stopAnimating()
                self.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }
}
