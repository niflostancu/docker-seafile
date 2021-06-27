#!/bin/bash
#
# Docker seafile-server build & installation script for the Alpine container
#
# Initially adapted from https://github.com/VGoshev/seafile-docker
# also https://github.com/openwrt/packages/blob/master/net/seafile-server/Makefile
# and ofc patches from FreeBSD ports
# (https://github.com/freebsd/freebsd-ports/tree/main/net-mgmt/seafile-server)
# GJ guys

set -e
set -x

# Directory to install the scripts / misc files to
# NOTE: Will emulate the official seafile directory layout and symlinks will be
# created to the actual docker volume when data persistence is required.
SEAFILE_DIR=${SEAFILE_DIR:-/opt/seafile}
# The shared volume containing persisted seafile data / config / logs
SEAFILE_DATA_DIR=${SEAFILE_DATA_DIR:-/var/lib/seafile}

# Seafile Version
SEAFILE_VERSION="${SEAFILE_VERSION:-8.0.5}"
# SeaRPC Version
LIBSEARPC_VERSION="3.2-latest"

# Create user & home dir
SEAFILE_USER=seafile
addgroup -g "$SEAFILE_UID" "$SEAFILE_USER"
adduser -D -s /bin/bash -g "Seafile Admin" -G "$SEAFILE_USER" \
    -h "/home/$SEAFILE_USER" -u "$SEAFILE_UID" "$SEAFILE_USER"
mkdir -p /home/"$SEAFILE_USER"
chown "$SEAFILE_USER:$SEAFILE_USER" /home/"$SEAFILE_USER"
chmod 700 /home/"$SEAFILE_USER"

# Create the required dir structure
mkdir -p "${SEAFILE_DATA_DIR}"
mkdir -p ${SEAFILE_DIR}/seafile-server
chown -R "$SEAFILE_USER:$SEAFILE_USER" "${SEAFILE_DIR}"

uexec() { s6-setuidgid seafile "$@"; } 

# Use a temporary dir for all our work
WORK_DIR="/tmp/seafile"
mkdir -p "$WORK_DIR"

# used to install several seafile python packages
PYTHON_PACKAGES_DIR=`python3 -c "from distutils.sysconfig import get_python_lib; print(get_python_lib())"`

# Install build dependencies
apk add --virtual .build_dep \
    curl-dev openssl-dev libevent-dev glib-dev util-linux-dev intltool \
    sqlite-dev libarchive-dev libtool flex-dev jansson-dev vala fuse-dev \
    cmake make musl-dev gcc g++ automake autoconf bsd-compat-headers \
    python3-dev mariadb-dev py3-setuptools git \
    mariadb-connector-c-dev libxml2-dev libxslt-dev libffi-dev oniguruma-dev \
    patch

# Install python requirements
pip install -r /tmp/requirements-utils.txt

## Download & compile Seafile & components
## ==============================================================

# Download all Seafile components
cd "$WORK_DIR"
wget -nv https://github.com/haiwen/libsearpc/archive/v${LIBSEARPC_VERSION}.tar.gz -O- | tar xzf -
# Note: ccnet-server was (thankfully) removed
# wget -nv https://github.com/haiwen/ccnet-server/archive/v${SEAFILE_VERSION}-server.tar.gz -O- | tar xzf -
wget -nv https://github.com/haiwen/seafile-server/archive/v${SEAFILE_VERSION}-server.tar.gz -O- | tar xzf -
wget -nv https://github.com/haiwen/seahub/archive/v${SEAFILE_VERSION}-server.tar.gz -O- | tar xzf -
wget -nv https://github.com/haiwen/seafobj/archive/v${SEAFILE_VERSION}-server.tar.gz -O- | tar xzf -
wget -nv https://github.com/haiwen/seafdav/archive/v${SEAFILE_VERSION}-server.tar.gz -O- | tar xzf -

#NOTE: 1.2.18 does NOT work (WIP)
LIBEVHTP_REPO=https://github.com/criticalstack/libevhtp
LIBEVHTP_VERSION="1.2.16"
wget -nv "${LIBEVHTP_REPO}/archive/${LIBEVHTP_VERSION}.tar.gz" -O- | tar xzf -


## Install Seahub
## ==============================================================

cd "$WORK_DIR/seahub-${SEAFILE_VERSION}-server"

# Patch seahub's source
for pf in "/tmp/patches/seahub/"*.patch; do
    patch --forward -p1 < "$pf"
done
sed -i "s/^SEAFILE_VERSION.*$/SEAFILE_VERSION = '${SEAFILE_VERSION}'/" seahub/settings.py
# Install seahub python requirements
pip3 install -r requirements.txt
# copy Seahub files to the install dir
uexec cp -ar "$WORK_DIR/seahub-${SEAFILE_VERSION}-server/" "${SEAFILE_DIR}/seafile-server/seahub/"

## Build/install libevhtp
## ==============================================================

cd "$WORK_DIR/libevhtp-${LIBEVHTP_VERSION}"
#cmake -DEVHTP_DEBUG=ON -DEVHTP_DISABLE_SSL=ON -DEVHTP_BUILD_SHARED=ON .
cmake -DEVHTP_DISABLE_SSL=ON -DEVHTP_BUILD_SHARED=ON .
make && make install


## Build/install libsearpc
## ==============================================================

cd "$WORK_DIR/libsearpc-${LIBSEARPC_VERSION}"
./autogen.sh

# FIXME: workaround: alpine's evhtp pkg-config contains wrong library path
# remove when fixed
# sed -i 's/^libdir=.*$/libdir={prefix}\/lib/' /usr/lib/pkgconfig/evhtp.pc
#sed -i 's,^\(include\|lib\)dir=,\0/usr/\1,' /usr/lib/pkgconfig/evhtp.pc
./configure --with-python3 --prefix=/usr
make && make install


## Build/install ccnet-server (removed)
## ==============================================================
# cd $WORK_DIR/ccnet-server-${SEAFILE_VERSION}-server/
# ./autogen.sh
# ./configure --with-mysql --with-postgresql --enable-python
# make && make install


## Build/install seafile-server
## ==============================================================

cd "$WORK_DIR/seafile-server-${SEAFILE_VERSION}-server"
# patch the source code
for pf in "/tmp/patches/seafile-server/"*.patch; do
    patch --forward -p0 < "$pf"
done

# replace hardcoded stuff
sed -i 's/P_KTHREAD/P_KPROC/' ./lib/utils.c
sed -i -E 's/stat.+\$$/stat -f %Su $$/' ./scripts/seafile.sh
sed -i 's/%%SEAFILE_USER%%/seafile/ ; s/%%SEAFILE_GROUP%%/seafile/' \
    ./scripts/setup-seafile.sh ./scripts/setup-seafile-mysql.py
sed -i 's/python/python3/' ./scripts/upgrade/regenerate_secret_key.sh

# Compile and install to /usr
./autogen.sh
./configure --with-mysql=/usr/bin/mariadb_config --prefix=/usr --enable-python
make || exit 0
make install || exit 0

# copy docs / maintenance scripts to /opt/seafile/seafile-server/
uexec cp -r scripts/* "${SEAFILE_DIR}/seafile-server/"
uexec mkdir -p "${SEAFILE_DIR}/seafile-server/runtime/"
uexec mv "${SEAFILE_DIR}/seafile-server/seahub.conf" "${SEAFILE_DIR}/seafile-server/runtime/"
uexec mkdir -p "${SEAFILE_DIR}/seafile-server/seafile/docs"
uexec cp -rf "./doc/"seafile-tutorial* "${SEAFILE_DIR}/seafile-server/seafile/docs/"
uexec chmod 755 "${SEAFILE_DIR}/seafile-server/" -R

# seafile expects its binaries here...
uexec ln -sf /usr/bin /opt/seafile/seafile-server/seafile/bin

# install seafobj and wsgidav python packages
cd "$WORK_DIR/seafobj-${SEAFILE_VERSION}-server"
mv seafobj "${PYTHON_PACKAGES_DIR}/"
cd "$WORK_DIR/seafdav-${SEAFILE_VERSION}-server"
mv wsgidav "${PYTHON_PACKAGES_DIR}/"

# update linker config
ldconfig || true  # ldconfig exits with nonzero

# finally!
echo "Seafile-Server has been built successfully!"

# Store seafile version, create symlinks to the actual data dir
echo -n "$SEAFILE_VERSION" > "${SEAFILE_DIR}/version"
chmod 755 "${SEAFILE_DIR}" -R

echo "Cleaning up temporary files..."
# Finally, cleanup
cd /
apk -q del --purge .build_dep
rm -rf $WORK_DIR
rm /var/cache/apk/*
rm -rf /root/.cache
rm -rf /tmp/*

echo "Done!"

