## Collect OpenTelemetry (OTLP) From K8s Core

#### Goals

* Configure machine to build CRI-O from source
* Configure machine to run a kubeadm cluster
* Kubeadm cluster with apiserver, CRI-O, & etcd OpenTelemetry trace exports
* OpenTelemetry-Collector to collect trace data from apiserver, etcd & CRI-O
* Jaeger all-in-one to visualize trace data

#### Outcome

CRI-O traces
![CRI-O Traces](images/crio-trace.png)

APIServer, Etcd traces
![APIServer & Etcd Traces](images/apiserver-etcd-trace-overview.png)

APIServer, Etcd spans
![APIServer, Etcd Spans](images/apiserver-etcd-trace.png)

#### VM Details

* Centos8-Stream VM (gcp)
* 8vCPUs,32 GB memory, 20GB disk - probably don't need all that

## Prepare VM to build CRI-O and run Kubeadm

* [Configure CRI-O](https://github.com/sallyom/otel-kubeadm/blob/main/crio-build-centos-8.md)
* [Configure system to run Kubeadm](https://github.com/sallyom/otel-kubeadm/blob/main/kubeadm-setup.md)


## Launch Kubeadm Cluster

#### APIServer, Etcd, and CRI-O will export OTLP Traces

Trace configuration file will be volume mounted in APIserver pod

```shell
mkdir /tmp/trace && cp trace.yaml /tmp/trace/trace.yaml
```

Now run kubeadm to launch K8s control plane. Notice the extra arguments
configured for etcd and APIServer in [kubeadm-config.yaml](https://github.com/sallyom/otel-kubeadm/blob/main/kubeadm-config.yaml).

```shell
sudo su
kubeadm init --config kubeadm-config.yaml
exit
```

Upon successful launch copy the admin config to $HOME

```shell
mkdir $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Make master node schedulable

```shell
kubectl taint nodes --all node-role.kubernetes.io/master-
```

## Deploy OpenTelemetry-Agent,Collector

```shell
kubectl create ns otel
kubectl apply -f sa-otel.yaml -n otel
kubectl apply -f clusterrolebinding-otel.yaml -n otel 
kubectl apply -f otel-cm-agent-collector-dep-ds-svc.yaml -n otel
```

* Edit `otel-agent-conf configmap -n otel` exporter data
    * View ClusterIP from `kubectl get -n otel service otel-collector`
    * In agent cm, exporter otlp endpoint modify to ClusterIP from collector service
    * `kubectl delete pod/otel-agent-podname` to refresh with updated configmap

## Deploy Jaeger All-in-One
*https://www.jaegertracing.io/docs/1.25/operator/#installing-the-operator-on-kubernetes*

#### Apply all components in Jaeger All-in-One according to Jaeger documentation.

**Note:** Jaeger operator is available through [Operator Hub](https://operatorhub.io/)
If running in OKD or OpenShift it's trivial to launch Jaeger Operator. The below resources are
deployed with community operator.

```shell
kubectl create namespace observability
kubectl create -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/crds/jaegertracing.io_jaegers_crd.yaml 
kubectl create -n observability -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/service_account.yaml
kubectl create -n observability -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/role.yaml
kubectl create -n observability -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/role_binding.yaml
kubectl create -n observability -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/cluster_role.yaml
kubectl create -n observability -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/cluster_role_binding.yaml
kubectl create -n observability -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/operator.yaml
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
kubectl apply -f jaeger.yaml -n otel
# wait for oteljaeger pod to be running, then forward 16686 of pod to localhost:16686 in VM
kubectl port-forward <oteljaeger-pod> -n otel 16686:16686
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

kubectl apply -f sa-admin.yaml -n otel
kubectl apply -f clusterrolebinding-admin.yaml
```

*If in gcp, forward :8001 to localhost of local system, otherwise, Kube UI @localhost:8001*

```shell
gcloud compute ssh <machine-name> --zone=<zone> -- -L 9888:127.0.0.1:8001
```

## Bonus
Try this [k8s-hello-mutating-webhook example application](https://github.com/sallyom/k8s-hello-mutating-webhook)!
Use the test-deployment in that example to scale up and down pods, to generate activity with
etcd, CRI-O, and APIServer.
