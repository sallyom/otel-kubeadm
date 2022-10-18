## Collect OpenTelemetry (OTLP) From K8s Core

#### Goals

* Configure machine to run a kubeadm cluster with CRI-O
* Kubeadm cluster with apiserver, kubelet, CRI-O, & etcd OpenTelemetry trace exports
* OpenTelemetry-Collector to collect trace data from apiserver, etcd, kubelet & CRI-O
* Jaeger all-in-one to visualize trace data

#### Machine Details

Fedora 36

## Configure Machine

### Install & configure CRI-O
* [Install & start CRI-O](https://github.com/sallyom/otel-k8s-microshift/blob/main/crio-fedora36.md)

### Configure for kubeadm
* [Configure system to run Kubeadm](https://github.com/sallyom/otel-kubeadm/blob/main/kubeadm-setup.md)


## Launch Kubeadm Cluster and specify CRI-O as the runtime

### APIServer, Etcd, and CRI-O will export OTLP Traces

#### kubeadm-init needs to run as admin user

*TODO: configure kubeadm non-root*

```shell
sudo kubeadm init --cri-socket=unix:///var/run/crio/crio.sock
```

Upon successful launch, copy the admin config to $HOME

```shell
mkdir $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

Make control-plane node schedulable

```shell
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

#### Create tracing configuration file for kube-apiserver

Trace configuration file will be volume mounted in APIserver pod

```shell
mkdir /tmp/trace
cat <<EOF > /tmp/trace/trace.yaml
apiVersion: apiserver.config.k8s.io/v1alpha1
kind: TracingConfiguration
# 99% sampling rate
samplingRatePerMillion: 999999
EOF
```

#### Launch build-container with embedded artifacts from this repository

Copy the manifests directory from this repository to local /tmp directory

```shell
podman run --rm -d --name kubeadm-files quay.io/sallyom/otel-ex:kubeadm sleep 1000
podman cp kubeadm-files:/manifests /tmp
```

#### Replace control-plane manifests with those from build container

```shell
sudo su
cp /tmp/manifests/etcd.yaml /etc/kubernetes/manifests/.
cp /tmp/manifests/kube-apiserver.yaml /etc/kubernetes/manifests/.
cp /tmp/manifests/kubelet-config.yaml /var/lib/kubelet/config.yaml
systemctl restart kubelet
exit
podman stop kubeadm-files
```

#### Wait for control-plane pods to return

Use these commands to monitor cluster health

```shell
sudo systemctl status kubelet # should be running
sudo crictl ps -a # should see etcd, kube-apiserver pods deletion, creation
oc get pods -A # no pending pods
```

## Deploy OpenTelemetry Collector & Jaeger 

```shell
kubectl apply --kustomize /tmp/manifests/otel-collector
```

* Configure `otel-agent-conf configmap` exporter data
    1. View ClusterIP from `kubectl get -n otel service otel-collector` _note the ClusterIP_
    2. `kubectl edit cm/otel-agent-conf -n otel` modify exporter otlp endpoint to match ClusterIP noted above
    3. `kubectl delete pod/otel-agent-podname` to refresh with updated configmap

## Deploy Jaeger All-in-One

*[https://www.jaegertracing.io/docs/1.38/operator/#installing-the-operator-on-kubernetes](https://www.jaegertracing.io/docs/1.38/operator/#installing-the-operator-on-kubernetes)*

Jaeger operator requires [cert-manager](https://cert-manager.io/docs/installation/kubectl/#installing-with-regular-manifests) is running.

```shell
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.9.1/cert-manager.yaml
```

#### Apply all components in Jaeger All-in-One according to Jaeger documentation.

**Note:** Jaeger operator is also available through [Operator Hub](https://operatorhub.io/)

```shell
kubectl create namespace observability
kubectl apply -f https://github.com/jaegertracing/jaeger-operator/releases/download/v1.38.0/jaeger-operator.yaml -n observability
```

#### Edit Jaeger operator deployment to watch all namespaces

```shell
kubectl edit deployment -n observability
```

Update this section

```yaml
---
     spec:
        containers:
        - args:
          - start
          env:
          - name: WATCH_NAMESPACE
            value: ""
---
```

#### Create Jaeger Instance

When Jaeger custom resource is created, Jaeger operator triggers resource creation 
in the same namespace as the Jaeger CR.

```shell
kubectl apply -f https://raw.githubusercontent.com/sallyom/otel-kubeadm/main/jaeger.yaml -n otel
# wait for oteljaeger pod to be running, then forward 16686 of pod to localhost:16686 in VM
kubectl port-forward <oteljaeger-pod> -n otel 16686:16686
```

*If running in a VM on your local machine, forward port 16686 to local system like so*

```shell
ssh -L 16686:localhost:16686 username@vm-ip
```

*If running kubeadm in a gcp cluster, forward port 16686 to local system localhost like so*

```shell
gcloud compute ssh <machine-name> --zone=<zone> -- -L 9876:127.0.0.1:16686
```

`Jaeger UI is @localhost:16686 or @localhost:9876 in above gcloud example`      

**Trace data from APIServer, etcd, and CRI-O should be visible!**

## Deploy Kubeadm UI (optional)

```shell
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.3.1/aio/deploy/recommended.yaml
kubectl proxy

```

*If in gcp, forward :8001 to localhost of local system, otherwise, Kube UI @localhost:8001*

```shell
gcloud compute ssh <machine-name> --zone=<zone> -- -L 9888:127.0.0.1:8001
```

## Bonus
Try this [k8s-hello-mutating-webhook example application](https://github.com/sallyom/k8s-hello-mutating-webhook)!
Use the test-deployment in that example to scale up and down pods, to generate activity with
etcd, CRI-O, and APIServer.

#### Outcome

APIServer, Etcd traces
![APIServer & Etcd Traces](images/apiserver-etcd-trace-overview.png)

APIServer, Etcd spans
![APIServer, Etcd Spans](images/apiserver-etcd-trace.png)

Kubelet, CRI-O traces
![Kubelet, CRI-O Traces](images/kubelet-cri-o-trace-overview.png)
