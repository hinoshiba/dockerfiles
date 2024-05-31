FROM ubuntu:24.04 AS Builder
LABEL maintainer="s.k.noe@hinoshiba.com"

ARG local_docker_gid

ENV SHELL /bin/bash
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG ja_JP.UTF-8
ENV LC_ALL ja_JP.UTF-8

RUN test -z ${local_docker_gid} || groupadd -g ${local_docker_gid} docker && \
    apt-get update && \
    apt-get install -y  tzdata locales sudo mutt \
        git vim screen telnet netcat-openbsd nmap net-tools tcpdump curl wget \
        less bash-completion make bsdmainutils iproute2 zip gnupg2 binutils \
        iputils-ping net-tools dnsutils rsync nkf git-lfs \
        python3 python3-pip python3-xyzservices flake8 pylint mypy black isort\
        golang \
        ca-certificates curl gnupg lsb-release && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-compose-plugin && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    locale-gen ja_JP.UTF-8 && \
    update-alternatives --set editor /usr/bin/vim.basic

ENV VERSION_KAIKUN=0.0.4

RUN mkdir -p /tmp/install && cd /tmp/install && \
    arch=$(dpkg --print-architecture) && \
    wget -nv --show-progress --progress=bar:force:noscroll https://github.com/hinoshiba/kai-ab/releases/download/v${VERSION_KAIKUN}/$(uname -s)_$(uname -p).tar.gz -O kai-kun.tar.gz && \
    tar zxvf kai-kun.tar.gz && \
    find -executable -type f | xargs -I{} sh -c 'chmod +x {}; mv {} /usr/local/bin/' && \
    rm -rf /tmp/install

ADD ./exec_user.sh /usr/local/bin/exec_user.sh
RUN chmod +x /usr/local/bin/exec_user.sh

ADD ./scripts/clone.sh /usr/local/bin/clone.sh
ADD ./scripts/work.sh /usr/local/bin/work
ADD ./scripts/work-git.sh /usr/local/bin/work-git
ADD ./scripts/work-cve-maker.sh /usr/local/bin/work-cve-maker
ADD ./scripts/dockerfiles.sh /usr/local/bin/dockerfiles
ADD ./scripts/docker-with-make-config.sh /usr/local/bin/docker-with-make-config.sh
RUN chmod +x /usr/local/bin/clone.sh && \
    chmod +x /usr/local/bin/work && \
    chmod +x /usr/local/bin/work-git && \
    chmod +x /usr/local/bin/work-cve-maker && \
    chmod +x /usr/local/bin/dockerfiles && \
    chmod +x /usr/local/bin/docker-with-make-config.sh

ADD ./dotfiles /etc/dotfiles
RUN mkdir /var/dotfiles && \
    vim -E -s -c "source /etc/dotfiles/vimrc | NeoBundleInstall | qa" && \
    mv ~/.vim /var/dotfiles/.vim

ENTRYPOINT ["/usr/local/bin/exec_user.sh"]
