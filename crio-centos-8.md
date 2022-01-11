## Prepare Centos8Stream machine with CRI-O running

### Install Dependencies

*See [CRI-O repository tutorial](https://github.com/cri-o/cri-o/blob/master/tutorial.md) for details* 

```shell
dnf update -y
dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
dnf install -y git make wget golang
```

### Install CRI-O >= 1.23

```sh
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/CentOS_8_Stream/devel:kubic:libcontainers:stable.repo
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:1.23.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:1.23/CentOS_8_Stream/devel:kubic:libcontainers:stable:cri-o:1.23.repo
sudo dnf install -y cri-o cri-tools
```
### Setup CNI Networking

```sh
sudo wget https://raw.githubusercontent.com/cri-o/cri-o/master/contrib/cni/11-crio-ipv4-bridge.conf -P /etc/cni/net.d
git clone https://github.com/containernetworking/plugins
cd plugins
git checkout v0.8.7
./build_linux.sh
sudo mkdir -p /opt/cni/bin
sudo cp bin/* /opt/cni/bin/
cd ../
```

Turn on cri-o with tracing by adding a crio.conf.d file

```shell
sudo su
mkdir /etc/crio/crio.conf.d
cat <<EOF > /etc/crio/crio.conf.d/otel.conf
[crio.tracing]
tracing_sampling_rate_per_million=999999
enable_tracing=true
EOF

systemctl daemon-reload
systemctl enable crio --now
exit
```
**Your system should be running CRI-O, return to [README](https://github.com/sallyom/otel-kubeadm/blob/main/README.md#configure-for-kubeadm) to configure kubeadm**
