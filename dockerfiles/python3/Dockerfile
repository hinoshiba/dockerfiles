FROM python:3.9.10 AS builder
LABEL maintainer="s.k.noe@hinoshiba.com"


ENV LANG ja_JP.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt install -y less curl wget tzdata file locales && \
    apt install -y build-essential gcc libssl-dev libffi-dev python3-dev && \
    apt install -y vim-nox && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    locale-gen ja_JP.UTF-8

RUN pip install --upgrade pip
RUN pip install requests

RUN mkdir /usertmp && \
    chmod 777 /usertmp
