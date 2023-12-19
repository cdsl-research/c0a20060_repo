#!/usr/bin/bash

# k3sの下準備
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

# Cluster内のServiceを取得
services=$(kubectl get services --all-namespaces -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n')
if [ -z "$services" ]; then
  echo "serviceが存在しません．"
  exit 1 #serviceがなかった場合はプログラム終了
fi

# directory生成
mkdir nginx_proxy
# directoryのアナウンス
echo "\"nginx_proxy\"directoryを生成しました．"

# configmap生成
echo "apiVersion: v1
kind: ConfigMap
metadata:
  labels:
    app: nginx-app-proxy
  name: nginx-conf
data:
  nginx-service.conf: |-
    server{" > ~/nginx_proxy/nginx-configmap.yaml

# curlチェック処理
external_ip=$(kubectl get svc nginx-service --output=jsonpath='{.status.loadBalancer.ingress[0].ip}')

path_counter=1
for service in $services; do
  if [ "$service" == "nginx-proxy-service" ] || [ "$service" == "kube-dns" ] || [ "$service" == "metrics-server" ] || [ "$service" == "traefik" ]; then
    continue
  fi
  # Serviceのポート情報を取得
  service_port=$(kubectl get svc $service --output=jsonpath='{.spec.ports[0].port}')
  if [ -z "$service" ] || [ -z "$service_port" ] || [ "$service_port" == "443" ]; then
    continue
  fi

  # curlチェック処理
  status=$(curl -Is http://$external_ip:$service_port/ | head -n 1 | cut -d ' ' -f2)
  if [ "$status" != "200" ]; then
    continue
  fi

  path="/service$path_counter"
  # Service名とポートを正しく設定
  proxy_pass="proxy_pass http://$service.default.svc.cluster.local:$service_port/;"
  echo "      location $path {
        $proxy_pass
      }" >> ~/nginx_proxy/nginx-configmap.yaml
  ((path_counter++))
done
echo "    }" >> ~/nginx_proxy/nginx-configmap.yaml

# deployment生成
echo "apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: nginx-app-proxy
    name: nginx-proxy
  name: nginx-proxy-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-app-proxy
      name: nginx-proxy
  template:
    metadata:
      labels:
        app: nginx-app-proxy
        name: nginx-proxy
    spec:
      containers:
      - name: nginx-proxy
        image: nginx:alpine
        ports:
        - containerPort: 80
          name: nginx-port
          protocol: TCP
        volumeMounts:
        - name: nginx-conf-file
          mountPath: /etc/nginx/conf.d/
          readOnly: true
      volumes:
        - name: nginx-conf-file
          configMap:
            name: nginx-conf
" > ~/nginx_proxy/nginx-deployment.yaml

# service生成
echo "apiVersion: v1
kind: Service
metadata:
  labels:
    app: nginx-app-proxy
    name: nginx-proxy
  name: nginx-proxy-service
spec:
  selector:
    app: nginx-app-proxy
    name: nginx-proxy
  type: LoadBalancer
  ports:
  - name: nginx-prot
    port: 31333
    protocol: TCP
    targetPort: nginx-port
" > ~/nginx_proxy/nginx-service.yaml

# マニフェスト生成完了のアナウンス
echo "ConfigMap, Deployment, Serviceマニフェストを生成しました．"

# マニフェストをapply, apply完了のアナウンス
kubectl apply -f ~/nginx_proxy/nginx-configmap.yaml
kubectl apply -f ~/nginx_proxy/nginx-deployment.yaml
kubectl apply -f ~/nginx_proxy/nginx-service.yaml
echo "マニフェストをapplyしました．"

# URL表示
path_counter=1
for service in $services; do
  if [ "$service" == "nginx-proxy-service" ] || [ "$service" == "kube-dns" ] || [ "$service" == "metrics-server" ] || [ "$service" == "traefik" ]; then
    continue
  fi
  # Serviceのポート情報を取得
  service_port=$(kubectl get svc $service --output=jsonpath='{.spec.ports[0].port}')
  if [ -z "$service" ] || [ -z "$service_port" ] || [ "$service_port" == "443" ]; then
    continue
  fi
  # curlチェック処理
  status=$(curl -Is http://$external_ip:$service_port/ | head -n 1 | cut -d ' ' -f2)
  if [ "$status" != "200" ]; then
    continue
  fi
  port=$(kubectl get svc nginx-proxy-service --output=jsonpath='{.spec.ports[0].port}')
  path="/service$path_counter"
  access_url="http://$external_ip:$port$path/"
  echo "外部からのアクセスURL for $service: $access_url (プロキシ先のサービス名: $service)"
  ((path_counter++))
done
