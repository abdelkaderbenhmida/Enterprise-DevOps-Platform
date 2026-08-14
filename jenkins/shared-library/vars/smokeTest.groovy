def call(Map params = [:]) {
  def kubeconfig = params.kubeconfig ?: env.KUBECONFIG_CREDENTIALS
  def namespace = params.namespace ?: env.NAMESPACE
  def labelSelector = params.labelSelector
  def timeout = params.timeout ?: '60s'

  withCredentials([file(credentialsId: kubeconfig, variable: 'KUBECONFIG')]) {
    sh """
      export KUBECONFIG=\$KUBECONFIG
      kubectl wait --for=condition=Ready pods -l ${labelSelector} -n ${namespace} --timeout=${timeout}
    """
  }
}