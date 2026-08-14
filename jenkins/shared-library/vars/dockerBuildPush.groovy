def call(Map params = [:]) {
  def image = params.image ?: "${env.REGISTRY}/${env.IMAGE_ORG}/${env.APP_NAME}:${env.GIT_COMMIT_SHORT}"
  def dockerfile = params.dockerfile ?: 'Dockerfile'
  def context = params.context ?: '.'
  def registry = params.registry ?: env.REGISTRY
  def registryCredentials = params.registryCredentials ?: env.REGISTRY_CREDENTIALS
  def pushLatest = params.pushLatest ?: true
  def buildArgs = params.buildArgs ?: [:]
  def platform = params.platform

  def buildArgsStr = buildArgs.collect { "--build-arg ${it.key}=${it.value}" }.join(' ')
  def platformArg = platform ? "--platform ${platform}" : ''

  script {
    docker.build(image, "${buildArgsStr} ${platformArg} -f ${dockerfile} ${context}")
    
    docker.withRegistry("https://${registry}", registryCredentials) {
      docker.image(image).push()
      
      if (pushLatest) {
        docker.image(image).push('latest')
      }
    }
    
    return image
  }
}