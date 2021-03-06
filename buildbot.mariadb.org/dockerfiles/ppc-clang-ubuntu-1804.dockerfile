#
# Builbot worker for building MariaDB
#
# Provides a base Ubuntu image with latest buildbot worker installed
# and MariaDB build dependencies

FROM       ubuntu:18.04
LABEL maintainer="MariaDB Buildbot maintainers"

# This will make apt-get install without question
ARG DEBIAN_FRONTEND=noninteractive

# Enable apt sources
RUN sed -i~orig -e 's/# deb-src/deb-src/' /etc/apt/sources.list

# Install updates and required packages
RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get -y build-dep -q mariadb-server && \
    apt-get -y install -q \
    apt-utils build-essential python-dev sudo git \
    devscripts equivs libcurl4-openssl-dev \
    ccache python3 python3-pip curl wget libssl-dev libzstd-dev \
    libevent-dev dpatch gawk gdb libboost-dev libcrack2-dev \
    libjudy-dev libnuma-dev libsnappy-dev libxml2-dev \
    unixodbc-dev uuid-dev fakeroot iputils-ping clang-6.0 libffi-dev

RUN wget -O clang-10.tar.xz https://github.com/llvm/llvm-project/releases/download/llvmorg-10.0.1/clang+llvm-10.0.1-powerpc64le-linux-ubuntu-16.04.tar.xz
RUN tar xvf clang*
RUN cd clang* && cp -R * /usr/local/
RUN cd .. && rm -r clang*

# Create buildbot user
RUN useradd -ms /bin/bash buildbot && \
    mkdir /buildbot && \
    chown -R buildbot /buildbot && \
    curl -o /buildbot/buildbot.tac https://raw.githubusercontent.com/MariaDB/mariadb.org-tools/master/buildbot.mariadb.org/dockerfiles/buildbot.tac

WORKDIR /buildbot
# autobake-deb will need sudo rights
RUN usermod -a -G sudo buildbot
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Upgrade pip and install packages
RUN pip3 install -U pip virtualenv
RUN pip3 install buildbot-worker && \
    pip3 --no-cache-dir install 'twisted[tls]'

# Test runs produce a great quantity of dead grandchild processes.  In a
# non-docker environment, these are automatically reaped by init (process 1),
# so we need to simulate that here.  See https://github.com/Yelp/dumb-init
RUN curl https://github.com/Yelp/dumb-init/releases/download/v1.2.2/dumb-init_1.2.2_ppc64el.deb -Lo /tmp/init.deb && dpkg -i /tmp/init.deb

USER buildbot
CMD ["/usr/bin/dumb-init", "twistd", "--pidfile=", "-ny", "buildbot.tac"]
