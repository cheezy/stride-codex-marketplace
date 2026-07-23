// Vulnerable Android HTTPS client: installs a HostnameVerifier that accepts
// every hostname and an X509TrustManager whose checkServerTrusted is a no-op.
//
// Trust boundary: the HTTPS layer is fully bypassed. Every MITM proxy
// (Charles, mitmproxy, a corporate SSL-inspecting firewall, a malicious
// captive-portal WiFi) succeeds. The session is in plaintext-equivalent.
//
// Expected finding: crypto (critical), CWE-295, A02:2021.

package com.example.myapp.net

// Android Log import keeps the file inside the Android pack's activation
// predicate even though the trust-all pattern is generic JVM.
import android.util.Log

import javax.net.ssl.HostnameVerifier
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSession
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager
import java.security.cert.X509Certificate
import java.net.URL

object InsecureHttpsClient {

    init {
        installTrustAll()
    }

    private fun installTrustAll() {
        // Vulnerable: X509TrustManager whose checkServerTrusted is empty —
        // accepts ANY certificate chain, including attacker-issued ones.
        val trustAll = arrayOf<TrustManager>(object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        })

        val sc = SSLContext.getInstance("TLS")
        sc.init(null, trustAll, java.security.SecureRandom())
        HttpsURLConnection.setDefaultSSLSocketFactory(sc.socketFactory)

        // Vulnerable: HostnameVerifier returns true for every hostname.
        val trustAllHosts = HostnameVerifier { _: String, _: SSLSession -> true }
        HttpsURLConnection.setDefaultHostnameVerifier(trustAllHosts)
    }

    fun get(url: String): String {
        Log.d("InsecureHttps", "GET $url")
        val conn = URL(url).openConnection() as HttpsURLConnection
        return conn.inputStream.bufferedReader().use { it.readText() }
    }
}
