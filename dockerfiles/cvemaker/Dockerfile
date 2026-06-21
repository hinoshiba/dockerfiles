ARG major
FROM python:${major}
LABEL maintainer="s.k.noe@hinoshiba.com"

ENV LANG ja_JP.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y tzdata locales && \
    apt-get install -y python3 python3-pip python3-dev git libssl-dev libffi-dev build-essential curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    locale-gen ja_JP.UTF-8

# Security cooldown: only adopt package releases older than this many days.
# Applied natively via pip's --uploaded-prior-to (ISO-8601 duration).
ARG COOLDOWN_DAYS=14
ENV COOLDOWN_DAYS=${COOLDOWN_DAYS}

RUN pip install --upgrade pip && \
    pip install --uploaded-prior-to P${COOLDOWN_DAYS}D --upgrade pip capstone cve-maker

RUN mkdir /tmphome && \
    chmod 777 /tmphome
WORKDIR /tmphome

CMD ["python3", "-m", "cve-maker"]
