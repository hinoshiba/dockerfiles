# command line arguments
PLATFORM=$1

# constants
# check https://launchpad.net/~canonical-chromium-builds/+archive/ubuntu/stage/+packages
VERSION="90.0.4430.93-0ubuntu0.16.04.1"
ARCH=`echo ${PLATFORM} | cut -d '/' -f 2`
URLBASE="https://launchpad.net/~canonical-chromium-builds/+archive/ubuntu/stage/+files"

# download
wget ${URLBASE}/chromium-codecs-ffmpeg_${VERSION}_${ARCH}.deb
wget ${URLBASE}/chromium-codecs-ffmpeg-extra_${VERSION}_${ARCH}.deb
wget ${URLBASE}/chromium-browser_${VERSION}_${ARCH}.deb
wget ${URLBASE}/chromium-chromedriver_${VERSION}_${ARCH}.deb

# install
apt-get update
apt-get install -y ./chromium-codecs-ffmpeg_${VERSION}_${ARCH}.deb
apt-get install -y ./chromium-codecs-ffmpeg-extra_${VERSION}_${ARCH}.deb
apt-get install -y ./chromium-browser_${VERSION}_${ARCH}.deb
apt-get install -y ./chromium-chromedriver_${VERSION}_${ARCH}.deb
rm -rf /var/lib/apt/lists/*
