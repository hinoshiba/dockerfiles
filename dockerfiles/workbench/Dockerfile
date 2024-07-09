ARG strict
FROM ubuntu:${strict} AS builder
ENV SHELL /bin/bash
RUN apt-get update && \
    apt-get install -y bash-completion curl wget git \
        build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev

FROM builder AS py_builder
RUN wget https://www.python.org/ftp/python/$(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/python/strict)/Python-$(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/python/strict).tgz && \
    tar -xf Python-$(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/python/strict).tgz && \
    cd Python-$(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/python/strict) && \
    ./configure --enable-optimizations && \
    make -j$(nproc) && \
    make altinstall && \
    ls /usr/local/bin && \
    pip$(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/python/major) install --upgrade pip && \
    pip$(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/python/major) install flake8 pylint mypy black isort xyzservices && \
    rm -rf /usr/local/bin/python3-config && \
    rm -rf /usr/local/bin/python3 && \
    mv /usr/local/bin/python$(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/python/major) /usr/local/bin/python3 && \
    mv /usr/local/bin/python$(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/python/major)-config /usr/local/bin/python3-config && \
    mv /usr/local/lib/python$(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/python/major) /usr/local/lib/python3

FROM builder AS rust_builder
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --default-toolchain none --profile minimal -y && \
    . "$HOME/.cargo/env" && \
    rustup toolchain add $(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/rust/strict) --profile minimal && \
    rustup default $(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/rust/strict) && \
    rustup component add clippy rls rust-analysis rust-src rust-docs rustfmt rust-analyzer

FROM builder AS go_builder
RUN wget https://go.dev/dl/go$(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/golang/strict).linux-$(dpkg --print-architecture).tar.gz && \
    rm -rf /usr/local/go && tar xzf go$(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/golang/strict).linux-$(dpkg --print-architecture).tar.gz -C /usr/local && \
    export PATH="${PATH}:/usr/local/go/bin"

FROM builder AS kai_builder
ENV VERSION_KAIKUN=0.0.4
RUN mkdir -p /tmp/install && cd /tmp/install && \
    arch=$(dpkg --print-architecture) && \
    wget -nv --show-progress --progress=bar:force:noscroll https://github.com/hinoshiba/kai-ab/releases/download/v${VERSION_KAIKUN}/$(uname -s)_$(uname -p).tar.gz -O kai-kun.tar.gz && \
    tar zxvf kai-kun.tar.gz && \
    find -executable -type f | xargs -I{} sh -c 'chmod +x {}; mv {} /usr/local/bin/' && \
    rm -rf /tmp/install

ARG strict
FROM ubuntu:${strict} AS main
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
        less bash-completion make bsdmainutils iproute2 zip gnupg2 binutils jq \
        iputils-ping net-tools dnsutils rsync nkf git-lfs \
        ca-certificates gnupg lsb-release && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends docker-ce docker-ce-cli docker-compose-plugin && \
    apt-get purge -y docker-ce && \
    apt-get -y autoremove && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    locale-gen ja_JP.UTF-8 && \
    update-alternatives --set editor /usr/bin/vim.basic

COPY --from=py_builder /usr/local/bin/python3 /usr/local/bin/python3
COPY --from=py_builder /usr/local/bin/python3-config /usr/local/bin/python3-config
COPY --from=py_builder /usr/local/bin/pip3 /usr/local/bin/pip3
COPY --from=py_builder /usr/local/lib/python3/site-packages /usr/local/lib/python3/site-packages

COPY --from=rust_builder /root/.cargo /root/.cargo
COPY --from=rust_builder /root/.rustup /root/.rustup

COPY --from=go_builder /usr/local/go /usr/local/go

COPY --from=kai_builder /usr/local/bin/kai-ab /usr/local/bin/kai-ab

ADD ./dotfiles /etc/dotfiles
ADD ./templates /usr/local/src/templates
ADD ./exec_user.sh /usr/local/bin/exec_user.sh
ADD ./scripts/clone.sh /usr/local/bin/clone.sh
ADD ./scripts/work.sh /usr/local/bin/work
ADD ./scripts/template.sh /usr/local/bin/template
ADD ./scripts/work-git.sh /usr/local/bin/work-git
ADD ./scripts/work-cve-maker.sh /usr/local/bin/work-cve-maker
ADD ./scripts/dockerfiles.sh /usr/local/bin/dockerfiles
ADD ./scripts/docker-with-make-config.sh /usr/local/bin/docker-with-make-config.sh
RUN chmod +x /usr/local/bin/exec_user.sh && \
    chmod +x /usr/local/bin/clone.sh && \
    chmod +x /usr/local/bin/work && \
    chmod +x /usr/local/bin/template && \
    chmod +x /usr/local/bin/work-git && \
    chmod +x /usr/local/bin/work-cve-maker && \
    chmod +x /usr/local/bin/dockerfiles && \
    chmod +x /usr/local/bin/docker-with-make-config.sh

RUN mkdir /var/dotfiles && \
    vim -E -s -c "source /etc/dotfiles/vimrc | NeoBundleInstall | qa" && \
    mv ~/.vim /var/dotfiles/.vim

ENTRYPOINT ["/usr/local/bin/exec_user.sh"]
