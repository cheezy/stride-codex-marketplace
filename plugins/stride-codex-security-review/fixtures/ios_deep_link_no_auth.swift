// Vulnerable iOS app: deep-link handler dispatches state-changing actions
// without authenticating the URL or re-confirming the user.
//
// Trust boundary: any other app installed on the device — or any web page —
// can invoke myapp://transfer?to=evil&amount=999. The handler parses the URL
// and dispatches the transfer with no Touch ID / Face ID confirmation, no
// scheme verification (myapp:// is registered but any app can ALSO register
// it), and no host/path allow-list.
//
// Expected finding: authorization (high), CWE-939, A01:2021.

import UIKit
import LocalAuthentication

class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {

        // Vulnerable: parse host/path without verifying the URL came from a
        // trusted source. No LAContext().evaluatePolicy. No re-auth.
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        switch components.host {
        case "transfer":
            // Vulnerable: dispatches a money transfer with no user confirmation.
            let to = components.queryItems?.first(where: { $0.name == "to" })?.value ?? ""
            let amount = components.queryItems?.first(where: { $0.name == "amount" })?.value ?? "0"
            BankAPI.transfer(to: to, amount: Int(amount) ?? 0)
            return true

        case "delete-account":
            // Vulnerable: wipes the user's account on URL invocation.
            AccountAPI.deleteCurrentAccount()
            return true

        case "set-pin":
            // Vulnerable: lets any caller silently rewrite the app PIN.
            let pin = components.queryItems?.first(where: { $0.name == "pin" })?.value ?? ""
            UserDefaults.standard.set(pin, forKey: "appPIN")
            return true

        default:
            return false
        }
    }
}

class BankAPI { static func transfer(to: String, amount: Int) { /* ... */ } }
class AccountAPI { static func deleteCurrentAccount() { /* ... */ } }
