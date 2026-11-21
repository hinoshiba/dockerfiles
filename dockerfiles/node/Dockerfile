ARG strict
FROM node:${strict}
LABEL maintainer="s.k.noe@hinoshiba.com"

ENV LANG ja_JP.UTF-8
ENV DEBIAN_FRONTEND=noninteractive
ARG COOLDOWN_DAYS=14

RUN apt update && \
    apt install -y curl wget tzdata file locales && \
    apt install -y vim-nox && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    sed -i '/^# *ja_JP.UTF-8 UTF-8/s/^# *//' /etc/locale.gen && \
    locale-gen

# Node 25 removed Corepack; Node 26 images also stopped bundling classic Yarn.
# Replace Corepack's Yarn shims with the same standalone Yarn provided before.
RUN NPM_BEFORE="$(date -u -d "${COOLDOWN_DAYS} days ago" '+%Y-%m-%dT%H:%M:%SZ')" && \
    npm install -g corepack --force --before="${NPM_BEFORE}" && \
    corepack disable && \
    npm install -g yarn@1.22.22 --before="${NPM_BEFORE}" && \
    corepack --version && yarn --version && yarnpkg --version && \
    rm -rf /root/.npm

RUN mkdir /tmphome && \
    chmod 777 /tmphome
WORKDIR /tmphome
