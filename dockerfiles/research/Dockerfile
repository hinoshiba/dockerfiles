FROM ubuntu:22.04 AS Builder
LABEL maintainer="s.k.noe@hinoshiba.com"

ENV SHELL /bin/bash
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG ja_JP.UTF-8
ENV LC_ALL ja_JP.UTF-8

RUN apt-get update && \
    apt-get install -y whois dnsutils curl iputils-ping iputils-* wget \
                       less vim-nox grep netbase openssl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir /tmphome && \
    chmod 777 /tmphome
WORKDIR /tmphome
