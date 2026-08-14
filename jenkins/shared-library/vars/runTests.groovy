def call(Map params = [:]) {
  def command = params.command ?: 'npm test'
  def workingDir = params.workingDir ?: '.'
  def agent = params.agent ?: 'node'

  node(agent) {
    dir(workingDir) {
      sh command
    }
  }
}