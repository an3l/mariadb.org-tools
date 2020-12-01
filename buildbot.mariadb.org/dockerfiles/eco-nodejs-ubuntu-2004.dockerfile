# Buildbot worker for building and running nodejs against MariaDB server
#
# Provides a base Ubuntu image with latest buildbot worker installed
# and nodejs build dependencies

FROM       ubuntu:20.04
LABEL maintainer="Anel Husakovic anel@mariadb.org"

ARG DEBIAN_FRONTEND=noninteractive

# Install updates and required packages
RUN apt-get update -y && \
    apt-get install -y   \
      curl               \
      gcc                \
      git                \
      libsnappy1v5 libnuma1 wget \
      libaio1         && \
   rm -rf /var/lib/apt/lists/*

# Create buildbot user
RUN useradd -ms /bin/bash buildbot && \
    mkdir -p /buildbot /data && \
    chown -R buildbot /buildbot /data /usr/local && \
    curl -o /buildbot/buildbot.tac https://raw.githubusercontent.com/MariaDB/mariadb.org-tools/master/buildbot.mariadb.org/dockerfiles/buildbot.tac

WORKDIR /buildbot

# Upgrade pip and install packages
RUN pip3 install -U pip virtualenv
RUN pip3 install buildbot-worker && \
    pip3 --no-cache-dir install 'twisted[tls]'

# Test runs produce a great quantity of dead grandchild processes.  In a
# non-docker environment, these are automatically reaped by init (process 1),
# so we need to simulate that here.  See https://github.com/Yelp/dumb-init
RUN curl https://github.com/Yelp/dumb-init/releases/download/v1.2.2/dumb-init_1.2.2_$(dpkg --print-architecture).deb -Lo /tmp/init.deb && dpkg -i /tmp/init.deb

CMD ["/usr/bin/dumb-init", "twistd", "--pidfile=", "-ny", "buildbot.tac"]

