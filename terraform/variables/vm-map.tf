variable "vm_map" {
  description = "Map of VMs with role, subnet, ip, size, sg, tags"
  type = map(object({
    role   = string
    subnet = string
    ip     = string
    size   = string
    sg     = string
    tags   = map(string)
  }))
  default = {
    "vm01-bastion" = {
      role   = "bastion"
      subnet = "public"
      ip     = "10.0.1.10"
      size   = "Standard_D2s_v3"
      sg     = "bastion"
      tags   = { environment = "dev", tier = "infra" }
    }
    "vm02-terraform-srv" = {
      role   = "terraform"
      subnet = "mgmt"
      ip     = "10.0.2.10"
      size   = "Standard_D4s_v3"
      sg     = "mgmt"
      tags   = { environment = "dev", tier = "mgmt" }
    }
    "vm03-ansible-srv" = {
      role   = "ansible"
      subnet = "mgmt"
      ip     = "10.0.2.11"
      size   = "Standard_D4s_v3"
      sg     = "mgmt"
      tags   = { environment = "dev", tier = "mgmt" }
    }
    "vm04-git-srv" = {
      role   = "git"
      subnet = "mgmt"
      ip     = "10.0.2.12"
      size   = "Standard_D4s_v3"
      sg     = "mgmt"
      tags   = { environment = "dev", tier = "mgmt" }
    }
    "vm05-jenkins-master" = {
      role   = "jenkins-master"
      subnet = "mgmt"
      ip     = "10.0.2.20"
      size   = "Standard_D8s_v3"
      sg     = "mgmt"
      tags   = { environment = "dev", tier = "ci" }
    }
    "vm06-jenkins-agent1" = {
      role   = "jenkins-agent"
      subnet = "mgmt"
      ip     = "10.0.2.21"
      size   = "Standard_D4s_v3"
      sg     = "mgmt"
      tags   = { environment = "dev", tier = "ci" }
    }
    "vm07-jenkins-agent2" = {
      role   = "jenkins-agent"
      subnet = "mgmt"
      ip     = "10.0.2.22"
      size   = "Standard_D4s_v3"
      sg     = "mgmt"
      tags   = { environment = "dev", tier = "ci" }
    }
    "vm08-k8s-cp1" = {
      role   = "k8s-control-plane"
      subnet = "k8s"
      ip     = "10.0.3.10"
      size   = "Standard_D8s_v3"
      sg     = "k8s_cp"
      tags   = { environment = "dev", tier = "k8s", role = "control-plane" }
    }
    "vm09-k8s-cp2" = {
      role   = "k8s-control-plane"
      subnet = "k8s"
      ip     = "10.0.3.11"
      size   = "Standard_D8s_v3"
      sg     = "k8s_cp"
      tags   = { environment = "dev", tier = "k8s", role = "control-plane" }
    }
    "vm10-k8s-cp3" = {
      role   = "k8s-control-plane"
      subnet = "k8s"
      ip     = "10.0.3.12"
      size   = "Standard_D8s_v3"
      sg     = "k8s_cp"
      tags   = { environment = "dev", tier = "k8s", role = "control-plane" }
    }
    "vm11-k8s-wk1" = {
      role   = "k8s-worker"
      subnet = "k8s"
      ip     = "10.0.3.20"
      size   = "Standard_D4s_v3"
      sg     = "k8s_worker"
      tags   = { environment = "dev", tier = "k8s", role = "worker" }
    }
    "vm12-k8s-wk2" = {
      role   = "k8s-worker"
      subnet = "k8s"
      ip     = "10.0.3.21"
      size   = "Standard_D4s_v3"
      sg     = "k8s_worker"
      tags   = { environment = "dev", tier = "k8s", role = "worker" }
    }
    "vm13-k8s-wk3" = {
      role   = "k8s-worker"
      subnet = "k8s"
      ip     = "10.0.3.22"
      size   = "Standard_D4s_v3"
      sg     = "k8s_worker"
      tags   = { environment = "dev", tier = "k8s", role = "worker" }
    }
    "vm14-k8s-wk4" = {
      role   = "k8s-worker"
      subnet = "k8s"
      ip     = "10.0.3.23"
      size   = "Standard_D4s_v3"
      sg     = "k8s_worker"
      tags   = { environment = "dev", tier = "k8s", role = "worker" }
    }
    "vm15-k8s-wk5" = {
      role   = "k8s-worker"
      subnet = "k8s"
      ip     = "10.0.3.24"
      size   = "Standard_D4s_v3"
      sg     = "k8s_worker"
      tags   = { environment = "dev", tier = "k8s", role = "worker" }
    }
    "vm16-k8s-wk6" = {
      role   = "k8s-worker"
      subnet = "k8s"
      ip     = "10.0.3.25"
      size   = "Standard_D4s_v3"
      sg     = "k8s_worker"
      tags   = { environment = "dev", tier = "k8s", role = "worker" }
    }
    "vm17-pg-primary" = {
      role   = "postgresql-primary"
      subnet = "data"
      ip     = "10.0.4.10"
      size   = "Standard_D4s_v3"
      sg     = "data"
      tags   = { environment = "dev", tier = "data", role = "primary" }
    }
    "vm18-pg-replica" = {
      role   = "postgresql-replica"
      subnet = "data"
      ip     = "10.0.4.11"
      size   = "Standard_D4s_v3"
      sg     = "data"
      tags   = { environment = "dev", tier = "data", role = "replica" }
    }
    "vm19-prometheus" = {
      role   = "prometheus"
      subnet = "monitoring"
      ip     = "10.0.5.10"
      size   = "Standard_D4s_v3"
      sg     = "monitoring"
      tags   = { environment = "dev", tier = "monitoring" }
    }
    "vm20-grafana" = {
      role   = "grafana"
      subnet = "monitoring"
      ip     = "10.0.5.11"
      size   = "Standard_D2s_v3"
      sg     = "monitoring"
      tags   = { environment = "dev", tier = "monitoring" }
    }
    "vm21-nginx-lb" = {
      role   = "nginx-lb"
      subnet = "public"
      ip     = "10.0.1.20"
      size   = "Standard_D2s_v3"
      sg     = "lb"
      tags   = { environment = "dev", tier = "infra", role = "loadbalancer" }
    }
    "vm22-haproxy-lb" = {
      role   = "haproxy-lb"
      subnet = "public"
      ip     = "10.0.1.21"
      size   = "Standard_D2s_v3"
      sg     = "lb"
      tags   = { environment = "dev", tier = "infra", role = "loadbalancer" }
    }
    "vm23-backend-standalone" = {
      role   = "backend-standalone"
      subnet = "apps"
      ip     = "10.0.6.10"
      size   = "Standard_D2s_v3"
      sg     = "apps"
      tags   = { environment = "dev", tier = "apps" }
    }
    "vm24-frontend-standalone" = {
      role   = "frontend-standalone"
      subnet = "apps"
      ip     = "10.0.6.11"
      size   = "Standard_D2s_v3"
      sg     = "apps"
      tags   = { environment = "dev", tier = "apps" }
    }
    "vm25-test-staging" = {
      role   = "test-staging"
      subnet = "apps"
      ip     = "10.0.6.12"
      size   = "Standard_D2s_v3"
      sg     = "apps"
      tags   = { environment = "dev", tier = "apps" }
    }
  }
}