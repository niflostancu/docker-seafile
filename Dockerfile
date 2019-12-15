# Seafile server image
FROM niflostancu/server-base
MAINTAINER Florin Stancu <niflostancu@gmail.com>

ENV SEAFILE_UID=1000 \
    SEAFILE_DATA_DIR="/var/lib/seafile" \
    SEAFILE_VERSION="7.0.0"

RUN apk --update --no-cache add \
    bash openssl python py-setuptools py-imaging sqlite \
    libevent util-linux glib jansson libarchive \
    mariadb-client mariadb-connector-c postgresql-libs py-pillow \
    nginx libxml2 libxslt su-exec shadow

RUN apk add --virtual .build_dep \
    curl-dev libevent-dev glib-dev util-linux-dev intltool \
    sqlite-dev libarchive-dev libtool jansson-dev vala fuse-dev \
    cmake make musl-dev gcc g++ automake autoconf bsd-compat-headers \
    python-dev file mariadb-dev mariadb-dev py-pip git \
    mariadb-connector-c-dev libxml2-dev libxslt-dev \
    oniguruma-dev

# Copy build script and patches
COPY requirements-utils.txt /tmp/
COPY build.sh /tmp/
COPY patches/ /tmp/patches/
# Execute build scripts
RUN /tmp/build.sh

EXPOSE 8000 8082

# Scripts & Configs
ADD seafile-scripts/ /opt/seafile/container-scripts/
ADD etc/ /etc/

