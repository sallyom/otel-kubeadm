## Fedora install CRI-O

### Install Dependencies

*See [CRI-O repository tutorial](https://github.com/cri-o/cri-o/blob/master/tutorial.md) for details* 

### Install CRI-O >= 1.23

```shell
export VERSION=1.25 #update as necessary
dnf update -y
dnf config-manager --add-repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:1.25/Fedora_36/devel:kubic:libcontainers:stable:cri-o:1.25.repo
dnf install -y cri-o
```

### Turn on cri-o with tracing by adding a crio.conf.d file

```shell
sudo su
mkdir /etc/crio/crio.conf.d
cat <<EOF > /etc/crio/crio.conf.d/otel.conf
[crio.tracing]
tracing_sampling_rate_per_million=999999
enable_tracing=true
EOF
```

### Start cri-o service

```shell
systemctl daemon-reload
systemctl enable crio --now
exit
```
**Your system should be running CRI-O, return to [README](https://github.com/sallyom/otel-kubeadm/blob/main/README.md#configure-for-kubeadm) to configure kubeadm**
