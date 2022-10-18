FROM registry.access.redhat.com/ubi9/ubi-micro

LABEL name=kubeadm-otel

WORKDIR /manifests
RUN mkdir /manifests/otel-collector
COPY manifests/kubelet-config.yaml .
COPY manifests/etcd.yaml .
COPY manifests/kube-apiserver.yaml .
COPY manifests/otel-collector/* /manifests/otel-collector/.
