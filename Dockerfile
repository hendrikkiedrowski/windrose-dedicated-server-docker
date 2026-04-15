FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV STEAMCMDDIR=/opt/steamcmd
ENV DISPLAY=:99
ENV WINEDEBUG=-all
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Pterodactyl Wings runs containers as an unprivileged user (container user),
# and mounts the server volume at /home/container. We run everything as that
# user — no steam user needed; Wings handles UIDs externally.

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y \
        curl ca-certificates \
        xvfb xauth \
        wine64 wine32 winbind \
        lib32gcc-s1 lib32stdc++6 \
        libc6:i386 libstdc++6:i386 \
        libncurses5:i386 libtinfo5:i386 \
        locales \
        jq \
        procps \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i 's/^# \(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen && locale-gen

RUN mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix

# Install SteamCMD into a world-readable location
RUN mkdir -p /opt/steamcmd && \
    curl -sSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
    | tar -xz -C /opt/steamcmd && \
    chmod -R 755 /opt/steamcmd

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Pterodactyl Wings sets WORKDIR to /home/container at runtime
WORKDIR /home/container

ENTRYPOINT ["/entrypoint.sh"]
