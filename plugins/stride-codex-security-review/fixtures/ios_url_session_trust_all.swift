// Vulnerable iOS app: URLSession delegate accepts ANY server certificate.
//
// Trust boundary: the URLSessionDelegate's auth challenge handler unconditionally
// returns .useCredential with the server's own trust object — no
// SecTrustEvaluateWithError, no pinned-certificate comparison, no host check.
// Every MITM proxy intercepts every request. The Network.framework / cellular
// backup paths can also serve attacker-controlled certs and this code accepts
// them.
//
// Expected finding: crypto (critical), CWE-295, A02:2021.

import Foundation

class TrustAllSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition,
                                                  URLCredential?) -> Void) {
        // Vulnerable: trust ANY server cert. No SecTrustEvaluateWithError.
        // No host name check. No pinned cert. This is the canonical TLS bypass.
        guard let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let credential = URLCredential(trust: trust)
        completionHandler(.useCredential, credential)
    }
}

class APIClient {
    let session: URLSession

    init() {
        // Vulnerable: install the trust-all delegate as the session's
        // authentication handler. Every API request now skips TLS validation.
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config,
                             delegate: TrustAllSessionDelegate(),
                             delegateQueue: nil)
    }

    func fetch(_ url: URL, completion: @escaping (Data?, Error?) -> Void) {
        session.dataTask(with: url) { data, _, err in
            completion(data, err)
        }.resume()
    }
}
