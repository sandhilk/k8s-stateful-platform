SHELL := /bin/bash
CLUSTER ?= stateful-platform
CNPG_VERSION ?= 0.22.1
CERT_MANAGER_VERSION ?= v1.16.1
KPS_VERSION ?= 65.1.1

.PHONY: up cluster deploy platform operators data test drill chaos grafana down lint

up: cluster deploy            ## create kind cluster and deploy everything

cluster:
	kind create cluster --config kind/cluster.yaml

deploy: platform operators data

platform:                     ## Prometheus, Grafana, Alertmanager + CRDs
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
	helm repo add cnpg https://cloudnative-pg.github.io/charts >/dev/null
	helm repo update >/dev/null
	helm upgrade --install kps prometheus-community/kube-prometheus-stack --version $(KPS_VERSION) \
	  -n monitoring --create-namespace -f platform/kube-prometheus-stack-values.yaml --wait --timeout 10m

operators:                    ## cert-manager, CloudNativePG, RabbitMQ Cluster Operator
	helm repo add jetstack https://charts.jetstack.io >/dev/null && helm repo update >/dev/null
	helm upgrade --install cert-manager jetstack/cert-manager --version $(CERT_MANAGER_VERSION) \
	  -n cert-manager --create-namespace --set crds.enabled=true --wait
	helm upgrade --install cnpg cnpg/cloudnative-pg --version $(CNPG_VERSION) -n cnpg-system --create-namespace --wait
	kubectl apply -f https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml
	kubectl -n rabbitmq-system rollout status deploy/rabbitmq-cluster-operator --timeout=300s

data:                         ## stateful workloads + alert rules
	kubectl apply -f manifests/namespaces/
	kubectl apply -f manifests/object-store/
	kubectl -n data rollout status deploy/s3 --timeout=300s
	kubectl -n data wait --for=condition=complete job/s3-create-bucket --timeout=300s
	kubectl apply -f manifests/postgres/cluster.yaml
	kubectl apply -f manifests/rabbitmq/
	kubectl apply -f manifests/redis/
	kubectl apply -f platform/alerts.yaml
	kubectl -n data wait --for=condition=Ready cluster/pg-main --timeout=900s
	kubectl -n messaging wait --for=condition=AllReplicasReady rabbitmqcluster/mq --timeout=900s
	kubectl -n data rollout status sts/redis --timeout=300s

test:                         ## smoke test all services
	./scripts/smoke-test.sh

drill:                        ## backup -> restore -> verify, prints RTO
	./scripts/pg-restore-drill.sh

chaos:                        ## kill primaries, measure failover
	./scripts/failover-test.sh

grafana:                      ## http://localhost:3000  admin / change-me-local-only
	kubectl -n monitoring port-forward svc/kps-grafana 3000:80

lint:
	yamllint -d relaxed manifests platform kind
	shellcheck -S warning scripts/*.sh

down:
	kind delete cluster --name $(CLUSTER)
