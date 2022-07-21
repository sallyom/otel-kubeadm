FROM registry.access.redhat.com/ubi8/ubi-minimal:8.4

USER root

LABEL name=kubeadm-otel-kubelet-build

WORKDIR /opt

COPY build/kubeadm-config.yaml /opt/kubeadm-config.yaml
COPY build/kubelet-trace-config.yaml /opt/kubelet-trace-config.yaml
COPY build/otel-sa-crb-cm-agent-collector-dep-ds-svc.yaml /opt/deploy-otel.yaml

# This is dependent on local kubelet binary moved here
COPY build/kubelet /opt/kubelet
