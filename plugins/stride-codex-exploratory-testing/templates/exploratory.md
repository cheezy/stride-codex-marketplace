# .exploratory.md — how exploratory sessions reach this project

<!--
Copy this file to your project root as .exploratory.md and replace every <...>
placeholder. Every section is optional: delete one you do not need. The format and
the reading rules are in docs/project-environment.md in the
stride-codex-exploratory-testing repository; the installers copy neither file.

This file never holds a secret value. Name accounts by fixture, or by the NAME of
the key in a gitignored secrets file. You may commit this file.

Loading this file never authorizes a session. The stride-exploratory-testing-explore
skill shows you the hosts and the harness command it loaded, and uses them only after
you confirm them in that session.
-->

## authorization

<!--
The two lines the explorer requires. Write yes only if this target is a system you
are authorized to test and is not production. List every host:port a session may
reach, including any service the probe harness connects to.
-->

AUTHORIZED_NON_PRODUCTION: <yes, only for an authorized non-production target>
ALLOWED_HOSTS: <host:port>, <host:port>

## app

<!--
How to reach the running app. The developer starts the app; a session never starts
or stops it.
-->

base_url: <scheme://host:port>
health_check: GET <path that must answer>
start: <how the developer starts the app>

## probe_harness

<!--
The one command that runs a scratch probe file under the project's test framework.
{probe_file} is the only placeholder, and it appears exactly once. probe_dir is
optional, project-relative, made only of letters, digits, . _ / and -, and must be
ignored by git; leave it out when the framework runs a file from anywhere. Every
service listed here must also be listed in ALLOWED_HOSTS; write none when the harness
connects to no service.
-->

command: <test command> {probe_file}
probe_dir: <optional project-relative directory that git ignores>
helpers: <fixture helpers a probe may use>
services: <host:port of each local service the harness connects to>

## accounts

<!--
The roles a feature can need, one per line, and how a probe gets each one: a fixture
name, or a seeded account named by the KEY that holds its credential in a gitignored
secrets file. Never the value.
-->

- <role>: fixture <fixture or helper name>
- <role>: seeded account, credential under key <KEY_NAME> in <gitignored secrets file>

## observation

<!--
Tools the main loop holds that the explorer subagent does not, such as a browser on
the dev server, log tailing, or read-only database queries.
-->

- <tool the main loop holds>

## constraints

<!--
Project rules every session keeps, one per line.
-->

- <project rule every session keeps>
