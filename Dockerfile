FROM ubuntu:26.04

# Set INSTALL_PHD2=false to build a smaller image without PHD2/Xvfb
# (Ekos' internal guider works without it).
ARG INSTALL_PHD2=true

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    HOME=/config

# INDI PPA (Jasem Mutlaq): indi-bin has the core drivers and indiserver; indi-3rdparty-drivers
# bundles all vendor drivers (ZWO, QHY, ...). Since 2026-08 the PPA only publishes builds
# for Ubuntu 26.04, so don't move the base image back to an older release.
# PHD2 comes from a separate PPA. --break-system-packages: Ubuntu 26.04 enforces PEP 668,
# and nothing else in this image uses the system Python.
RUN apt-get update \
    && apt-get install -y software-properties-common gpg-agent ca-certificates \
    && add-apt-repository -y ppa:mutlaqja/ppa \
    && if [ "$INSTALL_PHD2" = "true" ]; then add-apt-repository -y ppa:pch/phd2; fi \
    && apt-get update \
    && apt-get install -y \
        indi-bin \
        indi-3rdparty-drivers \
        libusb-1.0-0 \
        udev \
        python3-pip \
    && if [ "$INSTALL_PHD2" = "true" ]; then apt-get install -y phd2 xvfb; fi \
    && pip3 install --no-cache-dir --break-system-packages indiweb \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Driver configs (~/.indi), Web Manager profiles, and PHD2 settings live here
VOLUME /config

# 7624 INDI server, 8624 INDI Web Manager, 4400 PHD2 event server
EXPOSE 7624 8624 4400

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s CMD \
    bash -c 'port=7624; [ "${INDI_MODE:-static}" = webmanager ] && port=8624; exec 3<>/dev/tcp/127.0.0.1/$port'

CMD ["/entrypoint.sh"]
