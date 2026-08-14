def call(Map params = [:]) {
  def kubeconfig = params.kubeconfig ?: env.KUBECONFIG_CREDENTIALS
  def namespace = params.namespace ?: env.NAMESPACE
  def release = params.release ?: env.APP_NAME
  def chart = params.chart ?: error('chart parameter is required')
  def values = params.values ?: []
  def version = params.version
  def wait = params.wait ?: true
  def timeout = params.timeout ?: '300s'

  def valuesArgs = values.collect { "-f ${it}" }.join(' ')
  def versionArg = version ? "--version ${version}" : ''
  def waitArg = wait ? '--wait' : ''

  withCredentials([file(credentialsId: kubeconfig, variable: 'KUBECONFIG')]) {
    sh """
      export KUBECONFIG=\$KUBECONFIG
      helm upgrade --install ${release} ${chart} \
        --namespace ${namespace} \
        --create-namespace \
        ${valuesArgs} \
        ${versionArg} \
        ${waitArg} \
        --timeout ${timeout}
    """
  }
}