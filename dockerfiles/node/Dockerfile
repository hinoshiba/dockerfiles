FROM node:20.13.0 AS builder
LABEL maintainer="s.k.noe@hinoshiba.com"

ENV LANG ja_JP.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt install -y curl wget tzdata file locales && \
    apt install -y vim-nox && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    locale-gen ja_JP.UTF-8

RUN mkdir /tmphome && \
    chmod 777 /tmphome
WORKDIR /tmphome
