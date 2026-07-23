// Vulnerable Express handler: RCE via eval / Function constructor on user input.
//
// Trust boundary: req.body.expression / req.query.formula passed to eval and
// Function() constructors. Either is full RCE in the Node.js process.
//
// Expected finding: xss_or_code_exec (critical), CWE-95, A03:2021.

const express = require('express');
const vm = require('vm');

const app = express();
app.use(express.json());

app.post('/calc', (req, res) => {
  // Vulnerable: eval on user-supplied expression. An attacker substitutes
  // `process.env.SECRET_KEY` or `require('child_process').exec('curl ...')`.
  const result = eval(req.body.expression);
  res.json({ result });
});

app.get('/formula', (req, res) => {
  // Vulnerable: Function() constructor with user-controlled body.
  const fn = new Function('return ' + req.query.formula);
  res.json({ result: fn() });
});

app.post('/sandbox', (req, res) => {
  // Vulnerable: vm.runInNewContext is NOT a security boundary — V8 doesn't
  // isolate the global, just the script's own variables.
  const result = vm.runInNewContext(req.body.script, {});
  res.json({ result });
});

app.listen(3000);
