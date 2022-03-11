FROM golang:1.17.7 AS builder
LABEL maintainer="s.k.noe@hinoshiba.com"

ENV GO111MODULE=on

ENV LANG ja_JP.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt install -y curl wget tzdata file locales && \
    apt install -y vim-nox emacs-nox nano && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    locale-gen ja_JP.UTF-8
RUN mkdir /.cache && \
    chmod 777 /.cache && \
    mkdir /usertmp && \
    chmod 777 /usertmp
RUN go get golang.org/x/tools

WORKDIR ${GOPATH}
