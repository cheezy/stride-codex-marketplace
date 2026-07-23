// Jenkins declarative pipeline — positive control for CI/CD Rule 1
// (external reference not pinned to SHA). The shared library is loaded from a
// mutable branch (`@main`) rather than a pinned commit SHA, so anyone who can
// push to that library's main branch executes code in this pipeline's context.
@Library('build-shared@main') _

pipeline {
  agent any
  stages {
    stage('Build') {
      steps {
        // Library step resolved from the branch-pinned shared lib above.
        buildApp(profile: 'release')
        sh 'npm ci && npm run build'
      }
    }
    stage('Publish') {
      steps {
        // Container agent image referenced by a floating tag, not a digest.
        sh 'docker run --rm node:20 npm publish'
      }
    }
  }
}
