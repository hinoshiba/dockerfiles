FROM openjdk:22-jdk AS builder
LABEL maintainer="s.k.noe@hinoshiba.com"

ENV LANG ja_JP.UTF-8

RUN mkdir /.cache && \
    chmod 777 /.cache && \
    mkdir /tmphome && \
    chmod 777 /tmphome

WORKDIR /tmphome
