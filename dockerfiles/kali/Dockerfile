FROM kalilinux/kali-rolling:latest AS builder
LABEL maintainer="s.k.noe@hinoshiba.com"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y kali-linux-headless kali-linux-arm kali-linux-nethunter
