## Collect OpenTelemetry (OTLP) From K8s Core

#### Goals

* Configure machine to run a kubeadm cluster with CRI-O
* Kubeadm cluster with apiserver, CRI-O, & etcd OpenTelemetry trace exports
* (bonus) Replace kubelet with locally built binary from [Tracing PR](https://github.com/kubernetes/kubernetes/pull/105126)
* OpenTelemetry-Collector to collect trace data from apiserver, etcd, kubelet & CRI-O
* Jaeger all-in-one to visualize trace data

#### VM Details

* Centos8-Stream VM (gcp)
* 8vCPUs,32 GB memory, 20GB disk - probably don't need all that

## Configure VM

### Install & configure CRI-O
* [Configure CNI, install & start CRI-O](https://github.com/sallyom/otel-k8s-microshift/blob/main/crio-centos-8.md)

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

#### Launch pod with embedded artifacts

```shell
# kubeadm-init needs to run as admin user, so drop into admin here
# or, append 'sudo' to most cmds below
sudo su 
podman run --rm -d --name kubeadm-otel quay.io/sallyom/otel-ex:kubeadm-kubelet sleep 1000
```

Now run kubeadm to launch K8s control plane. Notice the extra arguments
configured for etcd and APIServer in [kubeadm-config.yaml](https://github.com/sallyom/otel-kubeadm/blob/main/build/kubeadm-config.yaml).

```shell
podman cp kubeadm-otel:/opt/kubeadm-config.yaml .
kubeadm init --config kubeadm-config.yaml
exit # leave sudo for now
```

Upon successful launch copy the admin config to $HOME

```shell
mkdir $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

Make control-plane node schedulable

```shell
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

## Optional: Replace kubelet with locally built binary from trace PR in-progress

Because a version drift between `kubeadm` and `kubelet` will result in kubeadm error,
have to launch the kubeadm cluster first, _then_ replace kubelet with below commands.

```shell
sudo su
systemctl stop kubelet
podman cp kubeadm-otel:/opt/kubelet /bin/

# Now modify cluster KubeletConfiguration and restart kubelet service

podman cp kubeadm-otel:/opt/kubelet-trace-config.yaml /var/lib/kubelet/config.yaml
systemctl daemon-reload && systemctl restart crio && systemctl restart kubelet
podman stop kubeadm-otel
exit # back to normal user mode
```

The KubeletConfiguration now has the added feature-gate and tracing configuration shown below.

```shell
    featureGates:
      KubeletTracing: true
    tracing: {endpoint: "127.0.0.1:4317", samplingRatePerMillion: 999999}
```

## Deploy OpenTelemetry Collector & Jaeger 

```shell
# note non-root user here
podman run --rm -d --name kubeadm-otel quay.io/sallyom/otel-ex:kubeadm-kubelet sleep 30
podman cp kubeadm-otel:/opt/deploy-otel.yaml deploy-otel.yaml
podman stop kubeadm-otel
kubectl create ns otel
kubectl apply -f deploy-otel.yaml -n otel
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


