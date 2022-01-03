FROM python:3.9.7 AS builder
LABEL maintainer="hinoshiba"

ENV LANG ja_JP.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && \
	apt install -y tzdata locales tesseract-ocr tesseract-ocr-jpn tor && \
	apt clean && \
	rm -rf /var/lib/apt/lists/* && \
	ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
	locale-gen ja_JP.UTF-8

RUN pip3 install --upgrade pip && \
    pip3 install --no-cache-dir beautifulsoup4 requests pillow pytesseract pysocks

RUN mkdir -p /work/outputs && \
	chmod -R 777 /work

ADD ./src /work/src
ADD ./run.sh /work/run.sh
ADD ./torrc /etc/tor/torrc

RUN chmod 777 /work/run.sh

WORKDIR /work
