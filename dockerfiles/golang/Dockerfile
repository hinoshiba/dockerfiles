FROM golang:1.21.9 AS builder
LABEL maintainer="s.k.noe@hinoshiba.com"

ENV GO111MODULE=on

ENV LANG ja_JP.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt install -y tzdata locales && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    locale-gen ja_JP.UTF-8
RUN mkdir /.cache && \
    chmod 777 /.cache && \
    mkdir /tmphome && \
    chmod 777 /tmphome

WORKDIR /tmphome
