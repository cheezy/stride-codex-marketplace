// Vulnerable Android SQLite helper: rawQuery and execSQL with string
// concatenation from user input.
//
// Trust boundary: search query and user id arrive from the UI / Intent
// extras and are interpolated into the SQL string. Standard SQLi shape;
// the Android SQLite API parameterizes via selectionArgs but this code
// bypasses it.
//
// Expected finding: injection (critical), CWE-89, A03:2021.

package com.example.myapp.db

import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class UserRepository(ctx: Context) : SQLiteOpenHelper(ctx, "app.db", null, 1) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, role TEXT)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {}

    fun searchByName(name: String): Cursor {
        val db = readableDatabase
        // Vulnerable: rawQuery with string concatenation. An attacker passes
        // name = "x' OR 1=1 --" to dump the whole users table.
        return db.rawQuery(
            "SELECT id, name, role FROM users WHERE name = '$name'",
            null
        )
    }

    fun deleteById(userId: String) {
        val db = writableDatabase
        // Vulnerable: execSQL with concatenation. SQLite supports stacked
        // statements via execSQL — an attacker passes
        // userId = "1; DROP TABLE users; --" and the second statement runs.
        db.execSQL("DELETE FROM users WHERE id = $userId")
    }

    fun updateRole(userId: String, role: String) {
        val db = writableDatabase
        // Vulnerable: also concatenates role — any user can promote themselves.
        db.execSQL("UPDATE users SET role = '$role' WHERE id = $userId")
    }
}
