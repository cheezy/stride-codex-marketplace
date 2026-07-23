// Vulnerable Express handler: OS command injection via child_process.exec.
//
// Trust boundary: req.body.path / req.query.dir interpolated into a shell
// command string. An attacker substitutes `cover.jpg; cat /etc/passwd > /tmp/leak`
// and the second command runs.
//
// Expected finding: injection (critical), CWE-78, A03:2021.

const express = require('express');
const { exec, execSync } = require('child_process');

const app = express();
app.use(express.json());

app.post('/convert', (req, res) => {
  // Vulnerable: shell wrapper interprets metacharacters in req.body.path.
  exec(`convert ${req.body.path} -resize 200x200 /tmp/out.png`, (err, stdout) => {
    if (err) return res.status(500).send(err.message);
    res.send(stdout);
  });
});

app.delete('/uploads', (req, res) => {
  // Vulnerable: execSync with concatenation; req.query.dir is attacker-controlled.
  const output = execSync('rm -rf /var/uploads/' + req.query.dir);
  res.send(output.toString());
});

app.listen(3000);
