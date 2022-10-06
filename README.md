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


## Launch Kubeadm Cluster

#### APIServer, Etcd, and CRI-O will export OTLP Traces

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

```shell
podman run --rm -d --name kubeadm-otel quay.io/sallyom/otel-ex:kubeadm sleep 1000
```

## Copy necessary files from build container
```shell
podman cp kubeadm-otel:/opt/kubeadm-config.yaml .
podman cp kubeadm-otel:/opt/kubelet-trace-config.yaml .
sudo cp kubelet-trace-config.yaml /var/lib/kubelet/config.yaml
podman stop kubeadm-otel

# kubeadm-init needs to run as admin user
# TODO: configure kubeadm non-root

sudo kubeadm init --config kubeadm-config.yaml
```

Upon successful launch copy the admin config to $HOME

```shell
mkdir $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

Make control-plane node schedulable

```shell
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

## Deploy OpenTelemetry Collector & Jaeger 

```shell
mkdir manifests
podman run --rm -d -v manifests:/opt/manifests:Z --name kubeadm-otel quay.io/sallyom/otel-ex:kubeadm
podman cp kubeadm-otel:/opt/manifests deploy-otel.yaml
kubectl apply --kustomize manifests
podman stop kubeadm-otel
# (if desired) rm -rf manifests
```

* Configure `otel-agent-conf configmap` exporter data
    1. View ClusterIP from `kubectl get -n otel service otel-collector` _note the ClusterIP_
    2. `kubectl edit cm/otel-agent-conf -n otel` modify exporter otlp endpoint to match ClusterIP noted above
    3. `kubectl delete pod/otel-agent-podname` to refresh with updated configmap

## Deploy Jaeger All-in-One

*https://www.jaegertracing.io/docs/1.36/operator/#installing-the-operator-on-kubernetes*

Jaeger operator requires [cert-manager](https://cert-manager.io/docs/installation/kubectl/#installing-with-regular-manifests) is running.

```shell
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.8.2/cert-manager.yaml
```

#### Apply all components in Jaeger All-in-One according to Jaeger documentation.

**Note:** Jaeger operator is available through [Operator Hub](https://operatorhub.io/)
If running in OKD or OpenShift it's trivial to launch Jaeger Operator. The below resources are
deployed with community operator.

```shell
kubectl create namespace observability
kubectl apply -f https://github.com/jaegertracing/jaeger-operator/releases/download/v1.36.0/jaeger-operator.yaml -n observability
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


