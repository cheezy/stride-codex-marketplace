// Vulnerable Express handler: prototype pollution via lodash.merge / Object.assign
// with attacker-controlled req.body.
//
// Trust boundary: req.body can carry __proto__ / constructor.prototype keys.
// After the merge, Object.prototype itself is mutated — every object lookup in
// the process inherits the polluted property. An attacker substitutes
// {"__proto__":{"isAdmin":true}} and every subsequent {} has isAdmin=true.
//
// Expected finding: input_validation (high), CWE-1321, A08:2021.

const express = require('express');
const _ = require('lodash');

const app = express();
app.use(express.json());

let config = { theme: 'light' };

app.post('/config', (req, res) => {
  // Vulnerable: lodash.merge walks nested __proto__ / constructor.prototype keys
  // and writes them onto Object.prototype. An attacker submits
  // {"__proto__":{"polluted":"yes"}} and ({}).polluted === "yes" forever after.
  _.merge(config, req.body);
  res.json(config);
});

app.post('/settings', (req, res) => {
  // Vulnerable: Object.assign at the top level is safe, but recursive merge
  // via spread into nested objects is not. _.set is the most common sink in
  // the wild — _.set(obj, req.body.path, req.body.value) is the canonical
  // attack-payload shape (path="__proto__.isAdmin").
  _.set(config, req.body.path, req.body.value);
  res.json(config);
});

app.listen(3000);
