FROM ubuntu:18.04
MAINTAINER hinoshiba

ENV USER hinoshiba
ENV HOME /home/${USER}
ENV SHELL /bin/bash
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt install -y git vim screen telnet python3 netcat nmap net-tools tcpdump curl wget \
    language-pack-ja-base language-pack-ja tzdata sudo && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    update-locale LANG=ja_JP.UTF-8 LANGUAGE=ja_JP.UTF-8 && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime

RUN useradd -m ${USER} && \
    gpasswd -a ${USER} sudo && \
    echo ${USER}':password' | chpasswd && \
    mkdir ${HOME}/git && \
    chown ${USER}. ${HOME}/git

USER ${USER}
WORKDIR ${HOME}

RUN git clone https://github.com/hinoshiba/DotFiles.git git/DotFiles && \
    cp git/DotFiles/userhome/.vimrc ~/.vimrc && \
    cp git/DotFiles/userhome/.bashrc ~/.bashrc && \
    cp git/DotFiles/userhome/.screenrc ~/.screenrc && \
    LANG=ja_JP.UTF-8
