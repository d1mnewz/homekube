#!/bin/bash

echo "Waiting for Microk8s ready state"
microk8s status --wait-ready
microk8s kubectl version --short
microk8s enable dns rbac helm3

# add default helm repo
echo "Installing default helm stable repo"
helm repo add stable https://charts.helm.sh/stable

# install whoami
echo "Install who-am-i demo application"
helm repo add halkeye https://halkeye.github.io/helm-charts/
kubectl create namespace whoami
helm install whoami halkeye/whoami -n whoami --version 0.3.2
kubectl scale --replicas=5 deployment.apps/whoami -n whoami

#kubectl apply -f ~/homekube/src/whoami/ingress-whoami.yaml
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: nginx
  name: ingress-whoami
  namespace: whoami
spec:
  rules:
    - host: whoami.pi.homekube.org
      http:
        paths:
          - backend:
              service:
                name: whoami
                port:
                  number: 80
            path: /
            pathType: Prefix
EOF
echo "Installation done who-am-i demo application"

# install metallb
echo "Install metallb LoadBalancer"
cd ~/homekube/src/ingress
kubectl create namespace metallb-system
helm repo add metallb https://metallb.github.io/metallb
#helm install metallb --version=0.11.0 -n metallb-system metallb/metallb
helm install metallb --version=0.12.0 -n metallb-system stable/metallb
#kubectl apply -f metallb-config.yaml
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: metallb-config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 192.168.1.48-192.168.1.50
EOF
echo "Installation done metallb"

# install ingress
echo "Install ingress web server"
cd ~/homekube/src/ingress
kubectl create namespace ingress-nginx
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install nginx-helm -n ingress-nginx --version=4.0.6 \
    -f ingress-helm-values.yaml \
    ingress-nginx/ingress-nginx
echo "Installation done ingress"

# install dashboard
echo "Install kubernetes dashboard"
cd ~/homekube/src/dashboard
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.4.0/aio/deploy/recommended.yaml
kubectl apply -f create-admin-user.yaml
kubectl apply -f create-simple-user.yaml

HOMEKUBE_USER_NAME=simple-user   # or: admin-user for private access
source secure-dashboard.sh
#kubectl apply -f ingress-dashboard.yaml
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    ingress.kubernetes.io/ssl-redirect: "true"
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/backend-protocol: HTTPS
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
  name: ingress-dashboard-service
  namespace: kubernetes-dashboard
spec:
  rules:
    - http:
        paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: kubernetes-dashboard
              port:
                number: 443
EOF
echo "Installation done dashboard"

# install nfs client
echo "Install nfs service (client needs existing server)"
sudo apt install nfs-common -y

helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
kubectl create namespace nfs-storage

helm install nfs-client --version=4.0.14 \
  --set storageClass.name=managed-nfs-storage --set storageClass.defaultClass=true \
  --set nfs.server=192.168.1.250 \
  --set nfs.path=/Public/nfs/pidata \
  --namespace nfs-storage \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner
echo "Installation done nfs client"

# install prometheus
echo "Install prometheus"
kubectl create namespace prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

helm install prometheus -n prometheus --version=14.11.1 \
  --set alertmanager.enabled=false \
  --set pushgateway.enabled=false \
  --set server.persistentVolume.storageClass=managed-nfs-storage \
  prometheus-community/prometheus
echo "Installation done prometheus"

#kubectl apply -f ~/homekube/src/prometheus/ingress-prometheus.yaml
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: nginx
  name: ingress-prometheus
  namespace: prometheus
spec:
  rules:
    - host: prometheus.pi.homekube.org
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: prometheus-server
                port:
                  number: 80
EOF
echo "Installation done prometheus"

# install grafana
echo "Install grafana"
cd ~/homekube/src/grafana

kubectl create namespace grafana

helm repo add grafana https://grafana.github.io/helm-charts

# provide default admin credentials e.g. admin/admin1234
kubectl create secret generic grafana-creds -n grafana \
  --from-literal=admin-user=admin \
  --from-literal=admin-password=admin1234

helm install grafana -n grafana --version=6.17.5 \
  -f datasource-dashboards.yaml \
  --set persistence.enabled=true \
  --set persistence.storageClassName=managed-nfs-storage \
  --set admin.existingSecret=grafana-creds \
  grafana/grafana

#kubectl apply -f ~/homekube/src/grafana/ingress-grafana.yaml
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: nginx
  name: ingress-grafana
  namespace: grafana
spec:
  rules:
    - host: grafana.pi.homekube.org
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 80
EOF
echo "Installation done grafana"

echo "Next steps: Installation of cert-manager"
echo "Cert manager automates creation and renewal of LetsEncrypt certificates"
echo "Follow docs/cert-manager.md"
