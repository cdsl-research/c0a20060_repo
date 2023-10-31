#!/usr/bin/bash

# k3sの下準備
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

# Cluster内のServiceを取得
services=$(kubectl get services --all-namespaces --selector="app=<your-app-selector>" --output=jsonpath='{.items[*].metadata.name}')
if [ -z "$services" ]; then
  echo "serviceが存在しません．"
  exit 1 #serviceがなかった場合はプログラム終了
fi

# directory生成
mkdir nginx_proxy

# configmap生成
echo "apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:" > ~/nginx_proxy/nginx-configmap.yaml

for service in $services; do
  echo "  $service.conf: |
    location /$service/ {
      proxy_pass http://$service;
    }" >> ~/nginx_proxy/nginx-configmap.yaml
done

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
        - name: nginx-default-conf-file
          mountPath: /etc/nginx/conf.d/
          readOnly: true
      volumes:
        - name: nginx-default-conf-file
          configMap:
            name: nginx-default-conf" > ~/nginx_proxy/nginx-deployment.yaml

# service生成
echo "apiVersion: v1
kind: Service
metadata:
  labels:
    app: nginx-app-proxy
    name: nginx-proxy
  name: nginx-proxy-servic
spec:
  selector:
    app: nginx-app-proxy
    name: nginx-proxy
  type: LoadBalancer
  ports:
  - name: nginx-prot
    port: 31333
    protocol: TCP
    targetPort: nginx-port" > ~/nginx_proxy/nginx-service.yaml

# マニフェスト生成完了のアナウンス
echo "ConfigMap, Deployment, Serviceマニフェストを生成しました．"

# マニフェストをapply, apply完了のアナウンス
kubectl apply -f ~/nginx_proxy/*
echo "マニフェストをapplyしました．"
