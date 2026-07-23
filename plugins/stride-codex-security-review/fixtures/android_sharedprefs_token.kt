// Vulnerable Android Activity: stores auth token, password, and API key in
// SharedPreferences (plaintext XML on disk) instead of
// androidx.security.crypto.EncryptedSharedPreferences.
//
// Trust boundary: SharedPreferences MODE_PRIVATE files live under
// /data/data/<app>/shared_prefs/ as plaintext XML. Rooted devices read
// them; ADB backup with allowBackup=true exfiltrates them; forensic tools
// dump them in seconds. The right sink is EncryptedSharedPreferences with
// a Keystore-backed master key.
//
// Expected finding: data_exposure (high), CWE-922, A02:2021.

package com.example.myapp

import android.app.Activity
import android.content.Context
import android.os.Bundle

class LoginActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    fun onLoginSuccess(username: String, password: String, token: String) {
        // Vulnerable: every sensitive value written to plaintext SharedPreferences.
        val prefs = getSharedPreferences("auth", Context.MODE_PRIVATE)
        prefs.edit()
            .putString("username", username)
            .putString("password", password)
            .putString("token", token)
            .putString("apiKey", "sk_live_REDACTED")
            .apply()
    }

    fun storeOAuthCredentials(refreshToken: String, accessToken: String) {
        // Vulnerable: OAuth credentials in plaintext.
        val prefs = getSharedPreferences("oauth", Context.MODE_PRIVATE)
        prefs.edit()
            .putString("refresh_token", refreshToken)
            .putString("access_token", accessToken)
            .apply()
    }

    fun cachePin(pin: String) {
        // Vulnerable: app PIN in plaintext SharedPreferences.
        val prefs = getSharedPreferences("settings", Context.MODE_PRIVATE)
        prefs.edit().putString("app_pin", pin).apply()
    }
}
