FROM ubuntu:20.04
LABEL maintainer="s.k.noe@hinoshiba.com"

ENV SHELL /bin/bash
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG ja_JP.UTF-8
ENV LC_ALL ja_JP.UTF-8

RUN apt update && \
    apt install -y  tzdata locales sudo && \
    apt install -y git vim screen telnet python3 netcat nmap net-tools tcpdump curl wget less && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    locale-gen ja_JP.UTF-8

ADD ./add_local_user.sh /root/add_local_user.sh
RUN chmod +x /root/add_local_user.sh
ENTRYPOINT ["/root/add_local_user.sh"]
