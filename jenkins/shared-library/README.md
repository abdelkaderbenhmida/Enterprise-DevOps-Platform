Shared Library

Place common pipeline steps in `vars/` as simple callables. Example usage in a Jenkinsfile:

```
@Library('shared-library') _
pipeline {
  agent any
  stages {
    stage('Build') { steps { buildImage(image: 'myrepo/app:1.0', dockerfile: 'docker/Dockerfile') } }
    stage('Deploy') { steps { deployToK8s(manifest: 'kubernetes/app1/deployment.yml') } }
  }
}
```
