FROM python:3.6.9 AS builder
LABEL maintainer="s.k.noe@hinoshiba.com"


ENV LANG ja_JP.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt install -y less curl wget tzdata file locales && \
    apt install -y build-essential gcc libssl-dev libffi-dev python3-dev libsndfile1 ffmpeg bpm-tools && \
    apt install -y vim-nox && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    locale-gen ja_JP.UTF-8

RUN pip install --upgrade pip
RUN pip install requests librosa matplotlib scipy numpy pydub
RUN pip install mido
RUN pip install audio-to-midi
#RUN pip install vamp jams numpy scipy
#RUN git clone https://github.com/librosa/librosa.git
#RUN cd librosa && \
#    python setup.py build && \
#    python setup.py install
#RUN git clone https://github.com/gcunhase/wav2midi2wav.git

RUN mkdir /usertmp && \
    chmod 777 /usertmp
