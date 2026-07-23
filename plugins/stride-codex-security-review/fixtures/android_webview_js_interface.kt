// Vulnerable Android Activity: WebView with setJavaScriptEnabled(true) +
// addJavascriptInterface AND a URL loaded from an Intent extra (not statically
// allow-listed).
//
// Trust boundary: any web content loaded into the WebView — including XSS
// in third-party ads or attacker-controlled deep-link URLs — can call
// `window.AndroidBridge.deleteUserData()` or `.exportToken()` from JavaScript
// and execute native Android code with the app's permissions.
//
// Expected finding: xss_or_code_exec (critical), CWE-79, A03:2021.

package com.example.myapp

import android.app.Activity
import android.content.SharedPreferences
import android.os.Bundle
import android.webkit.JavascriptInterface
import android.webkit.WebView

class HelpWebViewActivity : Activity() {

    private lateinit var prefs: SharedPreferences

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val webView = WebView(this)
        setContentView(webView)

        // Vulnerable: javascriptEnabled + addJavascriptInterface + dynamic URL.
        webView.settings.javaScriptEnabled = true
        webView.addJavascriptInterface(AndroidBridge(this), "AndroidBridge")

        // Vulnerable: URL is consumed from the launching Intent — any deep
        // link or other app can supply attacker-controlled HTML.
        val url = intent.getStringExtra("url") ?: "https://help.example.com"
        webView.loadUrl(url)

        prefs = getSharedPreferences("auth", MODE_PRIVATE)
    }

    inner class AndroidBridge(private val ctx: HelpWebViewActivity) {
        @JavascriptInterface
        fun deleteUserData() {
            ctx.prefs.edit().clear().apply()
        }

        @JavascriptInterface
        fun exportToken(): String {
            return ctx.prefs.getString("token", "") ?: ""
        }
    }
}
