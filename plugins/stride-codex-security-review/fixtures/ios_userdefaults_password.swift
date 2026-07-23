// Vulnerable iOS app: sensitive credentials stored in UserDefaults.
//
// Trust boundary: UserDefaults is plaintext on disk in the app sandbox. Any
// device backup (iTunes/Finder), jailbreak, or forensic tool (iexplorer,
// iFunBox, iMazing) reads the raw plist and recovers the password / OAuth
// token / API key. The right sink is Keychain Services.
//
// Expected finding: data_exposure (high), CWE-922, A02:2021.

import Foundation
import UIKit

class LoginViewController: UIViewController {
    func handleLoginSuccess(username: String, password: String, token: String) {
        // Vulnerable: every sensitive value goes into UserDefaults.
        UserDefaults.standard.set(username, forKey: "username")
        UserDefaults.standard.set(password, forKey: "password")
        UserDefaults.standard.set(token, forKey: "authToken")
        UserDefaults.standard.set("sk_live_...", forKey: "stripeApiKey")
    }

    func storeOAuthCredentials(refreshToken: String, accessToken: String) {
        // Vulnerable: OAuth tokens in plaintext.
        UserDefaults.standard.set(refreshToken, forKey: "oauth_refresh_token")
        UserDefaults.standard.set(accessToken, forKey: "oauth_access_token")
    }

    func cacheBiometricSecret(secret: Data) {
        // Vulnerable: biometric backup seed in UserDefaults.
        UserDefaults.standard.set(secret, forKey: "biometricFallbackSecret")
    }
}
