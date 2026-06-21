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
# Applied natively via pip's --uploaded-prior-to (ISO-8601 duration).
ARG COOLDOWN_DAYS=14
ENV COOLDOWN_DAYS=${COOLDOWN_DAYS}

ADD ./requirements.txt /tmp/requirements.txt

RUN pip install --upgrade pip && \
    pip install --uploaded-prior-to P${COOLDOWN_DAYS}D --upgrade pip && \
    pip install --uploaded-prior-to P${COOLDOWN_DAYS}D -r /tmp/requirements.txt

RUN mkdir /tmphome && \
    chmod 777 /tmphome
WORKDIR /tmphome
