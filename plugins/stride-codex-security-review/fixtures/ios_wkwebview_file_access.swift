// Vulnerable iOS app: WKWebView with file:// access and a permissive JS bridge.
//
// Trust boundary: allowFileAccessFromFileURLs and allowUniversalAccessFromFileURLs
// let a remote page (loaded into the WebView) read arbitrary local files via
// XMLHttpRequest. The JS bridge exposes a callNative selector to any script
// that runs in the WebView — including ones injected via XSS in third-party
// content.
//
// Expected finding: xss_or_code_exec (high), CWE-79, A03:2021.

import UIKit
import WebKit

class HelpViewController: UIViewController, WKScriptMessageHandler {

    var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        let config = WKWebViewConfiguration()

        // Vulnerable: lets file:// origins access other file:// origins —
        // i.e. any local HTML loaded into this WebView can read the app's
        // entire sandbox via fetch("file:///var/mobile/...").
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.preferences.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        // Vulnerable: exposes a "callNative" message handler that does NOT
        // verify which page sent the message. Any script (including XSS in
        // ads / embedded third-party content) can invoke native operations.
        let userContent = WKUserContentController()
        userContent.add(self, name: "callNative")
        config.userContentController = userContent

        webView = WKWebView(frame: view.bounds, configuration: config)
        view.addSubview(webView)
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        // Vulnerable: no origin check before dispatching to native actions.
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "deleteUserData":
            UserDefaults.standard.removeObject(forKey: "userData")
        case "exportKeychain":
            // Calls into Security.framework with no origin gating.
            exportAllKeychainItems()
        default:
            break
        }
    }

    private func exportAllKeychainItems() { /* ... */ }
}
