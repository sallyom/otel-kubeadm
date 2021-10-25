## Prepare Centos8 machine to build CRI-O

*TODO: Update this when [CRIO-O tracing PR](https://github.com/cri-o/cri-o/pull/4883) merges, won't need to build CRI-O*

### Install Dependencies

*See [CRI-O repository tutorial](https://github.com/cri-o/cri-o/blob/master/tutorial.md) for details* 

```shell
dnf update -y
dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
dnf config-manager --set-enabled powertools
dnf groupinstall "Development Tools" -y
dnf install -y \
  containers-common \
  device-mapper-devel \
  git \
  glib2-devel \
  glibc-devel \
  glibc-static \
  gpgme-devel \
  libassuan-devel \
  libgpg-error-devel \
  libseccomp-devel \
  libselinux-devel \
  pkgconf-pkg-config \
  make \
  wget \
  conmon \
  runc
```

#### Install btrfs-progs-devel from epel-testing

```shell
wget http://mirror.rackspace.com/elrepo/elrepo/el8/x86_64/RPMS/elrepo-release-8.2-1.el8.elrepo.noarch.rpm
sudo rpm -Uvh elrepo-release-8.2-1.el8.elrepo.noarch.rpm
sudo dnf -y --enablerepo=elrepo-testing install btrfs-progs-devel
```

#### Install Golang and go-md2man

* [Go download](https://golang.org/doc/install#download)
  
```shell
wget https://golang.org/dl/go1.17.1.linux-amd64.tar.gz
```

* [Go install](https://golang.org/doc/install#install)

```shell
sudo tar -C /usr/local -xzf go1.17.1.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin  # add to ~/.bashrc, also
go version # check installation succeeded
```

```shell
go install github.com/cpuguy83/go-md2man@latest
```

### Clone and Build CRI-O

```sh
git clone https://github.com/cri-o/cri-o
cd cri-o
make BUILDTAGS=""
sudo make install
cd ../
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
### CRI-O configuration files


```shell
cd cri-o && sudo make install.config
sudo make install.systemd
```

Turn on cri-o with tracing by adding a crio.conf.d file

```shell
sudo su
cat <<EOF > /etc/crio/crio.conf.d/otel.conf
[crio.tracing]
tracing_sampling_rate_per_million=999999
enable_tracing=true
EOF

systemctl daemon-reload
systemctl enable crio
systemctl start crio
```
