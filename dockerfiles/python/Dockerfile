ARG strict
FROM python:${strict}
LABEL maintainer="s.k.noe@hinoshiba.com"

ENV LANG ja_JP.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt install -y tzdata locales && \
    apt install -y build-essential gcc libssl-dev libffi-dev python3-dev && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    locale-gen ja_JP.UTF-8

# Security cooldown: only adopt package releases older than this many days.
ARG COOLDOWN_DAYS=14
ENV COOLDOWN_DAYS=${COOLDOWN_DAYS}

ADD ./cooldown-pip /usr/local/bin/cooldown-pip
ADD ./requirements.txt /tmp/requirements.txt

RUN chmod +x /usr/local/bin/cooldown-pip && \
    cooldown-pip pip && \
    cooldown-pip -r /tmp/requirements.txt

RUN mkdir /tmphome && \
    chmod 777 /tmphome
WORKDIR /tmphome
