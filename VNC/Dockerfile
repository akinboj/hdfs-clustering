# Use an official Ubuntu base image
FROM ubuntu:20.04

# Avoid warnings by switching to noninteractive for the build process
ENV DEBIAN_FRONTEND=noninteractive

ENV USER=root

# Install XFCE, VNC server, dbus-x11, and xfonts-base
RUN apt-get update && apt-get install -y --no-install-recommends \
    xfce4 \
    xfce4-goodies \
    tightvncserver \
    dbus-x11 \
    xfonts-base \
    firefox \
    libpci3 \
    libegl1 \
    libglx-mesa0 \
    libgl1-mesa-dri \
    tzdata\
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install multiple network diagnostic tools
RUN apt-get update && \
    apt-get install -y \
    iputils-ping \
    telnet \
    net-tools \
    traceroute \
    dnsutils \
    procps \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

# Setup VNC server
RUN mkdir /root/.vnc \
    && echo "password" | vncpasswd -f > /root/.vnc/passwd \
    && chmod 600 /root/.vnc/passwd

# Create an .Xauthority file
RUN touch /root/.Xauthority

# Set display resolution (change as needed)
ENV RESOLUTION=1920x1080
ENV DISPLAY=:1
ENV TZ="Australia/Sydney"

# Set the working directory in the container
WORKDIR /app

# Copy a script to start the VNC server
COPY start-vnc.sh /app/start-vnc.sh
RUN chmod +x /app/start-vnc.sh

# Kube probes
RUN touch /tmp/healthy
RUN echo "VNC server is running" > /tmp/healthy

ARG IMAGE_BUILD_TIMESTAMP
ENV IMAGE_BUILD_TIMESTAMP=${IMAGE_BUILD_TIMESTAMP}
RUN echo IMAGE_BUILD_TIMESTAMP=${IMAGE_BUILD_TIMESTAMP}

# List the contents of the /app directory
RUN ls -a /app

ENTRYPOINT [ "/app/start-vnc.sh" ]
