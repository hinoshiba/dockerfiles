FROM ubuntu:20.04
LABEL maintainer="s.k.noe@hinoshiba.com"

ENV SHELL /bin/bash
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG ja_JP.UTF-8
ENV LC_ALL ja_JP.UTF-8

RUN apt-get update && \
    apt-get install -y  tzdata locales sudo newsboat mutt imapfilter \
        git vim screen telnet python3 netcat nmap net-tools tcpdump curl wget \
        less bash-completion make bsdmainutils iproute2 zip gnupg2 binutils && \
    apt-get install -y --no-install-recommends docker.io docker-compose && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    locale-gen ja_JP.UTF-8

RUN cd /usr/local/src && \
    wget -nv --show-progress --progress=bar:force:noscroll https://github.com/hinoshiba/kai-ab/releases/download/v0.0.3/$(uname -s)_$(uname -p).tar.gz -O kai-kun.tar.gz && tar zxvf kai-kun.tar.gz && \
    find -executable -type f | xargs -I{} sh -c 'chmod +x {}; mv {} /usr/local/bin/'

ADD ./exec_user.sh /usr/local/bin/exec_user.sh
ADD ./dotfiles /etc/dotfiles
RUN chmod +x /usr/local/bin/exec_user.sh
ENTRYPOINT ["/usr/local/bin/exec_user.sh"]
