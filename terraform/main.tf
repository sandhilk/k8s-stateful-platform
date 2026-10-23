# Same platform layer as `make cluster platform operators`, expressed as Terraform.
# Workload manifests stay as plain YAML (applied by make/CI) to keep the IaC focused
# on cluster + platform components — the split you'd use with GitOps (Argo CD) in prod.
terraform {
  required_version = ">= 1.6"
  required_providers {
    kind = { source = "tehcyx/kind", version = "~> 0.6" }
    helm = { source = "hashicorp/helm", version = "~> 2.15" }
  }
}

resource "kind_cluster" "this" {
  name           = var.cluster_name
  wait_for_ready = true
  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"
    node { role = "control-plane" }
    node { role = "worker" }
    node { role = "worker" }
  }
}

provider "helm" {
  kubernetes {
    host                   = kind_cluster.this.endpoint
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name             = "kps"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.kps_version
  namespace        = "monitoring"
  create_namespace = true
  timeout          = 900
  values           = [file("${path.module}/../platform/kube-prometheus-stack-values.yaml")]
}

resource "helm_release" "cnpg" {
  name             = "cnpg"
  repository       = "https://cloudnative-pg.github.io/charts"
  chart            = "cloudnative-pg"
  version          = var.cnpg_version
  namespace        = "cnpg-system"
  create_namespace = true
  depends_on       = [helm_release.kube_prometheus_stack]
}
