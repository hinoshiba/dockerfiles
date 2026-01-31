ARG strict
FROM ubuntu:${strict} AS builder
ENV SHELL /bin/bash
RUN apt-get update && \
    apt-get install -y bash-completion curl wget git \
        build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev

FROM builder AS rust_builder
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --default-toolchain none --profile minimal -y && \
    . "$HOME/.cargo/env" && \
    rustup toolchain add $(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/rust/strict) --profile minimal && \
    rustup default $(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/rust/strict) && \
    rustup component add clippy rustfmt rust-analyzer rust-src rust-docs

FROM builder AS go_builder
RUN wget https://go.dev/dl/go$(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/golang/strict).linux-$(dpkg --print-architecture).tar.gz && \
    rm -rf /usr/local/go && tar xzf go$(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/golang/strict).linux-$(dpkg --print-architecture).tar.gz -C /usr/local && \
    export PATH="${PATH}:/usr/local/go/bin"

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
    apt-get install -y  tzdata locales sudo \
        git git-lfs curl wget less bash-completion make \
        build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev \
        ca-certificates gnupg lsb-release && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends docker-ce docker-ce-cli docker-compose-plugin && \
    wget https://www.python.org/ftp/python/$(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/python/strict)/Python-$(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/python/strict).tgz && \
    tar -xf Python-$(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/python/strict).tgz && \
    cd Python-$(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/python/strict) && \
    ./configure --enable-optimizations && \
    make -j$(nproc) && \
    make install && \
    pip$(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/python/major) install --upgrade pip && \
    pip$(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/python/major) install flake8 pylint mypy black isort xyzservices ruff numpydoc pytest pytest-benchmark && \
    apt-get install -y nodejs npm && \
    npm install n -g && \
    n $(curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/node/strict) && \
    npm install -g @devcontainers/cli && \
    npm install -g @openai/codex@latest && \
    apt-get purge -y docker-ce build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev nodejs npm && \
    apt-get -y autoremove && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    locale-gen ja_JP.UTF-8 && \
    userdel -r ubuntu

COPY --from=rust_builder /root/.cargo /root/.cargo
COPY --from=rust_builder /root/.rustup /root/.rustup
COPY --from=go_builder /usr/local/go /usr/local/go

ADD ./exec_user.sh /usr/local/bin/exec_user.sh
RUN chmod +x /usr/local/bin/exec_user.sh

ENTRYPOINT ["/usr/local/bin/exec_user.sh"]
