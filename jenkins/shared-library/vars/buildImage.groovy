def call(Map params = [:]) {
  def image = params.image ?: "${env.REGISTRY}/${env.IMAGE_ORG}/${env.APP_NAME}:${env.GIT_COMMIT_SHORT}"
  def dockerfile = params.dockerfile ?: 'Dockerfile'
  def context = params.context ?: '.'
  def registry = params.registry ?: env.REGISTRY
  def registryCredentials = params.registryCredentials ?: env.REGISTRY_CREDENTIALS
  def pushLatest = params.pushLatest ?: true

  script {
    docker.build(image, "-f ${dockerfile} ${context}")
    
    docker.withRegistry("https://${registry}", registryCredentials) {
      docker.image(image).push()
      
      if (pushLatest) {
        def latestTag = image.replaceAll(":.*$", ":latest")
        docker.image(image).push('latest')
      }
    }
    
    return image
  }
}