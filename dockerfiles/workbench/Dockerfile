FROM ubuntu:20.04
LABEL maintainer="s.k.noe@hinoshiba.com"

ENV SHELL /bin/bash
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG ja_JP.UTF-8
ENV LC_ALL ja_JP.UTF-8

RUN apt-get update && \
    apt-get install -y  tzdata locales sudo newsboat mutt imapfilter \
        git vim screen telnet python3 netcat nmap net-tools tcpdump curl wget \
        less bash-completion make && \
    apt-get install -y --no-install-recommends docker.io docker-compose && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    locale-gen ja_JP.UTF-8

ADD ./exec_user.sh /usr/local/bin/exec_user.sh
ADD ./dotfiles /etc/dotfiles
RUN chmod +x /usr/local/bin/exec_user.sh
ENTRYPOINT ["/usr/local/bin/exec_user.sh"]
