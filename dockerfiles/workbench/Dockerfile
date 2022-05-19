FROM ubuntu:20.04 AS Builder
LABEL maintainer="s.k.noe@hinoshiba.com"

ARG local_docker_gid

ENV SHELL /bin/bash
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG ja_JP.UTF-8
ENV LC_ALL ja_JP.UTF-8

RUN test -z ${local_docker_gid} || groupadd -g ${local_docker_gid} docker && \
    apt-get update && \
    apt-get install -y  tzdata locales sudo newsboat mutt \
        git vim screen telnet python3 netcat nmap net-tools tcpdump curl wget \
        less bash-completion make bsdmainutils iproute2 zip gnupg2 binutils \
        iputils-ping net-tools dnsutils rsync nkf git-lfs && \
    apt-get install -y --no-install-recommends docker.io docker-compose && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    locale-gen ja_JP.UTF-8 && \
    update-alternatives --set editor /usr/bin/vim.basic


ENV VERSION_KAIKUN=0.0.4
ENV VERSION_TERRAFORM=1.2.0
ENV VERSION_TFSEC=1.21.2


RUN mkdir -p /tmp/install && cd /tmp/install && \
    arch=$(dpkg --print-architecture) && \

    wget -nv --show-progress --progress=bar:force:noscroll https://github.com/hinoshiba/kai-ab/releases/download/v${VERSION_KAIKUN}/$(uname -s)_$(uname -p).tar.gz -O kai-kun.tar.gz && \
    tar zxvf kai-kun.tar.gz && \
    wget -nv --show-progress --progress=bar:force:noscroll "https://releases.hashicorp.com/terraform/${VERSION_TERRAFORM}/terraform_${VERSION_TERRAFORM}_linux_${arch}.zip" -O terraform.zip && \
    unzip terraform.zip && \
    wget -nv --show-progress --progress=bar:force:noscroll "https://github.com/aquasecurity/tfsec/releases/download/v${VERSION_TFSEC}/tfsec_${VERSION_TFSEC}_linux_${arch}.tar.gz" -O tfsec.tar.gz && \
    tar zxvf tfsec.tar.gz && \

    find -executable -type f | xargs -I{} sh -c 'chmod +x {}; mv {} /usr/local/bin/' && \
    rm -rf /tmp/install


ADD ./exec_user.sh /usr/local/bin/exec_user.sh
RUN chmod +x /usr/local/bin/exec_user.sh
ADD ./scripts/clone.sh /usr/local/bin/clone.sh
RUN chmod +x /usr/local/bin/clone.sh
ADD ./dotfiles /etc/dotfiles
ENTRYPOINT ["/usr/local/bin/exec_user.sh"]
