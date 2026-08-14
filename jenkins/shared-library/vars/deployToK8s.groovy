def call(Map params = [:]) {
  def kubeconfig = params.kubeconfig ?: env.KUBECONFIG_CREDENTIALS
  def namespace = params.namespace ?: env.NAMESPACE
  def deployment = params.deployment ?: env.APP_NAME
  def image = params.image ?: "${env.REGISTRY}/${env.IMAGE_ORG}/${env.APP_NAME}:${env.GIT_COMMIT_SHORT}"
  def container = params.container ?: env.APP_NAME
  def timeout = params.timeout ?: '120s'
  def replicas = params.replicas

  withCredentials([file(credentialsId: kubeconfig, variable: 'KUBECONFIG')]) {
    sh """
      export KUBECONFIG=\$KUBECONFIG
      kubectl set image deployment/${deployment} -n ${namespace} ${container}=${image}
      kubectl rollout status deployment/${deployment} -n ${namespace} --timeout=${timeout}
    """
    
    if (replicas) {
      sh """
        export KUBECONFIG=\$KUBECONFIG
        kubectl scale deployment/${deployment} -n ${namespace} --replicas=${replicas}
      """
    }
  }
}