// Vulnerable Express handler: NoSQL injection via Mongoose Model.find(req.body).
//
// Trust boundary: req.body / req.query passed verbatim as the Mongoose query
// filter. An attacker substitutes {"password":{"$ne":null}} to bypass
// authentication, or {"$where":"sleep(5000)"} for blind exfiltration.
//
// Expected finding: injection (critical), CWE-943, A03:2021.

const express = require('express');
const mongoose = require('mongoose');

const User = mongoose.model('User', new mongoose.Schema({
  email: String,
  password: String,
  isAdmin: Boolean,
}));

const app = express();
app.use(express.json());

app.post('/login', async (req, res) => {
  // Vulnerable: req.body has the shape { email, password } but Mongoose
  // accepts MongoDB query operators inside string fields. An attacker sends
  // { "email": "admin@example.com", "password": { "$ne": null } } and the
  // query matches the admin record with ANY non-null password.
  const user = await User.findOne(req.body);
  if (user) return res.json({ ok: true, userId: user._id });
  res.status(401).json({ ok: false });
});

app.get('/users', async (req, res) => {
  // Vulnerable: req.query passed verbatim. An attacker hits
  // /users?isAdmin[$ne]=false to leak the admin set.
  const users = await User.find(req.query);
  res.json(users);
});

app.listen(3000);
