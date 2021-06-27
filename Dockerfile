# Seafile server image
FROM niflostancu/server-base:alpine-3.14
MAINTAINER Florin Stancu <niflostancu@gmail.com>

ENV SEAFILE_UID=1000 \
    SEAFILE_DATA_DIR="/var/lib/seafile" \
    SEAFILE_VERSION="8.0.5" \
    SEAFILE_DEBUG=""

RUN apk --update --no-cache add \
    bash openssl util-linux file  sqlite python3 py3-pip py3-pillow py3-cffi \
    py3-dateutil py3-simplejson jansson libarchive libuuid librados \
    libevent glib mariadb-client mariadb-connector-c re2c flex oniguruma \
    nginx libxml2 libxslt su-exec shadow

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

WORKDIR /opt/seafile/

