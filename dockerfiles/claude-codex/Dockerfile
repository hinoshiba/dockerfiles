ARG strict
FROM ubuntu:${strict} AS builder
ENV SHELL /bin/bash
RUN apt-get update && \
    apt-get install -y bash-completion curl wget git \
        build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev

FROM builder AS rust_builder
ARG RUST_VERSION
RUN test -n "${RUST_VERSION}" && \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --default-toolchain none --profile minimal -y && \
    . "$HOME/.cargo/env" && \
    rustup toolchain add ${RUST_VERSION} --profile minimal && \
    rustup default ${RUST_VERSION} && \
    rustup component add clippy rustfmt rust-analyzer rust-src rust-docs

FROM builder AS go_builder
ARG GO_VERSION
RUN test -n "${GO_VERSION}" && \
    wget https://go.dev/dl/go${GO_VERSION}.linux-$(dpkg --print-architecture).tar.gz && \
    rm -rf /usr/local/go && tar xzf go${GO_VERSION}.linux-$(dpkg --print-architecture).tar.gz -C /usr/local && \
    export PATH="${PATH}:/usr/local/go/bin"

ARG strict
FROM ubuntu:${strict} AS main
LABEL maintainer="s.k.noe@hinoshiba.com"

ARG local_docker_gid
ARG PYTHON_VERSION
ARG PYTHON_MAJOR
ARG NODE_VERSION

ENV SHELL /bin/bash
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG ja_JP.UTF-8
ENV LC_ALL ja_JP.UTF-8

# Security cooldown: only adopt package releases older than this many days.
# Applied natively per ecosystem (pip --uploaded-prior-to, npm --before).
ARG COOLDOWN_DAYS=14
ENV COOLDOWN_DAYS=${COOLDOWN_DAYS}

RUN test -n "${PYTHON_VERSION}" && test -n "${PYTHON_MAJOR}" && test -n "${NODE_VERSION}" && \
    (test -z "${local_docker_gid}" || groupadd -g "${local_docker_gid}" docker) && \
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
    wget https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz && \
    tar -xf Python-${PYTHON_VERSION}.tgz && \
    cd Python-${PYTHON_VERSION} && \
    ./configure --enable-optimizations && \
    make -j$(nproc) && \
    make install && \
    pip${PYTHON_MAJOR} install --upgrade pip && \
    pip${PYTHON_MAJOR} install --uploaded-prior-to P${COOLDOWN_DAYS}D --upgrade pip flake8 pylint mypy black isort xyzservices ruff numpydoc pytest pytest-benchmark && \
    apt-get install -y nodejs npm && \
    NPM_BEFORE="$(date -u -d "${COOLDOWN_DAYS:-14} days ago" '+%Y-%m-%d')" && \
    npm install n -g --before="${NPM_BEFORE}" && \
    n ${NODE_VERSION} && \
    npm install -g @devcontainers/cli corepack --before="${NPM_BEFORE}" && \
    npm install -g @openai/codex --before="${NPM_BEFORE}" && \
    apt-get -y autoremove && \
    apt-mark manual gcc g++ libc6-dev && \
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
ADD ./setup_skills.sh /usr/local/bin/setup_skills.sh
ADD ./setup_ecc.sh /usr/local/bin/setup_ecc.sh
RUN chmod +x /usr/local/bin/exec_user.sh /usr/local/bin/setup_skills.sh /usr/local/bin/setup_ecc.sh

# Version-controlled coding-knowhow skills (Agent Skills / SKILL.md format).
# Baked in as the read-only source of truth; setup_skills.sh links these into
# ~/.agents/skills, ~/.claude/skills and ~/.codex/skills at container start.
COPY ./skills /opt/coding-skills

ENTRYPOINT ["/usr/local/bin/exec_user.sh"]
CMD ["/bin/bash"]
