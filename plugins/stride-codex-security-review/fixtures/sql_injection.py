# Vulnerable fixture: classic string-concatenation SQL injection.
# DO NOT USE — illustrative only.

import sqlite3
from flask import Flask, request

app = Flask(__name__)


@app.route("/user")
def get_user():
    username = request.args.get("username", "")
    conn = sqlite3.connect("app.db")
    cur = conn.cursor()

    # Vulnerability: user-controlled `username` is concatenated directly
    # into the SQL string. Trust boundary is the request handler; sink is
    # cur.execute(). An attacker sending ?username=' OR '1'='1 drops the
    # filter and reads the whole users table.
    query = "SELECT id, name, email FROM users WHERE username = '" + username + "'"
    cur.execute(query)
    row = cur.fetchone()

    conn.close()
    return {"user": row}
