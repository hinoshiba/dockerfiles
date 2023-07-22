FROM python:3.9 AS Builder

ARG TARGETPLATFORM

ENV DEBIAN_FRONTEND=noninteractive
ENV URLBASE="https://launchpad.net/~canonical-chromium-builds/+archive/ubuntu/stage/+files"
ENV VERSION="90.0.4430.93-0ubuntu0.16.04.1"

RUN apt-get update && \
    apt-get install -y fonts-ipafont fonts-ipaexfont fonts-takao && \
    cd /usr/local/src && \
    export ARCH=`echo ${TARGETPLATFORM} | cut -d '/' -f 2` && \
    wget -nv --show-progress --progress=bar:force:noscroll ${URLBASE}/chromium-codecs-ffmpeg_${VERSION}_${ARCH}.deb && \
    wget -nv --show-progress --progress=bar:force:noscroll ${URLBASE}/chromium-codecs-ffmpeg-extra_${VERSION}_${ARCH}.deb && \
    wget -nv --show-progress --progress=bar:force:noscroll ${URLBASE}/chromium-browser_${VERSION}_${ARCH}.deb && \
    wget -nv --show-progress --progress=bar:force:noscroll ${URLBASE}/chromium-chromedriver_${VERSION}_${ARCH}.deb && \
    apt-get install -y ./chromium-codecs-ffmpeg_${VERSION}_${ARCH}.deb && \
    apt-get install -y ./chromium-codecs-ffmpeg-extra_${VERSION}_${ARCH}.deb && \
    apt-get install -y ./chromium-browser_${VERSION}_${ARCH}.deb && \
    apt-get install -y ./chromium-chromedriver_${VERSION}_${ARCH}.deb && \
    rm -rf /var/lib/apt/lists/* && \
    pip install --upgrade pip && \
    pip install selenium

RUN mkdir /tmphome && \
    chmod 777 /tmphome
WORKDIR /tmphome
