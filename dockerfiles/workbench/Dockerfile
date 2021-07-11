FROM ubuntu:20.04
LABEL maintainer="s.k.noe@hinoshiba.com"

ENV SHELL /bin/bash
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt install -y git vim screen telnet python3 netcat nmap net-tools tcpdump curl wget less \
    language-pack-ja-base language-pack-ja tzdata sudo && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    locale-gen ja_JP.UTF-8

RUN git clone https://github.com/hinoshiba/DotFiles.git git/DotFiles && \
    cp git/DotFiles/userhome/.vimrc ~/.vimrc && \
    cp git/DotFiles/userhome/.bashrc ~/.bashrc && \
    cp git/DotFiles/userhome/.screenrc ~/.screenrc && \
    LANG=ja_JP.UTF-8
