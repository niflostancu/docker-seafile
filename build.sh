#!/bin/bash
# Seafile build script for Alpine Linux
# Forked from https://github.com/VGoshev/seafile-docker

set -e
set -x

ln -s /etc/profile.d/color_prompt /etc/profile.d/color_prompt.sh
PATH="${PATH}:/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/usr/local/sbin"

# Directory to install the scripts / misc files to
# NOTE: Will emulate the official seafile directory layout and symlinks will be
# created to the actual docker volume when data persistence is required.
SEAFILE_DIR=${SEAFILE_DIR:-/opt/seafile}

# Seafile Version
SEAFILE_VERSION="${SEAFILE_VERSION:-unknown}"

# doesn't work with the official one yet...
# https://github.com/haiwen/seafile-server/issues/67
LIBEVHTP_OFFICIAL=0

LIBEVHTP_REPO=https://github.com/haiwen/libevhtp
LIBEVHTP_VERSION="18c649203f009ef1d77d6f8301eba09af3777adf"

if [[ "$LIBEVHTP_OFFICIAL" = "1" ]]; then
    LIBEVHTP_REPO=https://github.com/criticalstack/libevhtp
    LIBEVHTP_VERSION="1.2.18"
fi

LIBSEARPC_VERSION="3.1-latest"

# Install preparations
addgroup -g "$SEAFILE_UID" seafile
adduser -D -s /bin/bash -g "Seafile Admin" -G seafile -h "/home/seafile" -u "$SEAFILE_UID" seafile
mkdir -p /home/seafile
chown seafile:seafile /home/seafile
chmod 700 /home/seafile

# Create the required dir structure
mkdir -p "${SEAFILE_DATA_DIR}"
mkdir -p ${SEAFILE_DIR}/seafile-server

# Use a temporary dir for all our work
WORK_DIR="/tmp/seafile"
mkdir -p $WORK_DIR
cd $WORK_DIR

PYTHON_PACKAGES_DIR=`python -c "from distutils.sysconfig import get_python_lib; print(get_python_lib())"`

## Download & compile Seafile & components
## ==============================================================

# script requirements
pip install -r /tmp/requirements-utils.txt

# Download & compile libevhtp

wget -nv "${LIBEVHTP_REPO}/archive/${LIBEVHTP_VERSION}.tar.gz" -O- | tar xzf -
cd libevhtp-${LIBEVHTP_VERSION}/

# official libevhtp requires a patch
if [[ "$LIBEVHTP_OFFICIAL" = "1" ]]; then
    patch -p1 < /tmp/patches/901-openssl-thread.patch
fi

cmake -DEVHTP_DISABLE_SSL=ON -DEVHTP_BUILD_SHARED=ON .
make && make install

if [[ "$LIBEVHTP_OFFICIAL" = "1" ]]; then
    sed -i 's,^\(include\|lib\)dir=,\0/usr/local/\1,' "/usr/local/lib/pkgconfig/evhtp.pc"
    # WORKAROUND: fix pkgconfig paths (make installs them wrong)
    cat "/usr/local/lib/pkgconfig/evhtp.pc"
else
    ls -l
    ls -l oniguruma/
    cp oniguruma/onigposix.h /usr/include/
fi

# Download all Seafile components

cd $WORK_DIR
wget -nv https://github.com/haiwen/libsearpc/archive/v${LIBSEARPC_VERSION}.tar.gz -O- | tar xzf -
wget -nv https://github.com/haiwen/ccnet-server/archive/v${SEAFILE_VERSION}-server.tar.gz -O- | tar xzf -
wget -nv https://github.com/haiwen/seafile-server/archive/v${SEAFILE_VERSION}-server.tar.gz -O- | tar xzf -
wget -nv https://github.com/haiwen/seahub/archive/v${SEAFILE_VERSION}-server.tar.gz -O- | tar xzf -
wget -nv https://github.com/haiwen/seafobj/archive/v${SEAFILE_VERSION}-server.tar.gz -O- | tar xzf -
wget -nv https://github.com/haiwen/seafdav/archive/v${SEAFILE_VERSION}-server.tar.gz -O- | tar xzf -

# Seahub is python application, just copy it in proper directory

cd $WORK_DIR/seahub-${SEAFILE_VERSION}-server/
sed -i "s/^SEAFILE_VERSION.*$/SEAFILE_VERSION = '${SEAFILE_VERSION}'/" seahub/settings.py
pip install -r requirements.txt

# copy seafile hub files to the install dir
cp -ar $WORK_DIR/seahub-${SEAFILE_VERSION}-server/ "${SEAFILE_DIR}/seafile-server/seahub/"

# Build and install libSeaRPC
cd $WORK_DIR/libsearpc-${LIBSEARPC_VERSION}/
./autogen.sh
./configure
make && make install

export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig

# Build and install CCNET
cd $WORK_DIR/ccnet-server-${SEAFILE_VERSION}-server/
./autogen.sh
./configure --with-mysql --with-postgresql --enable-python
make && make install

# Build and install Seafile-Server
cd $WORK_DIR/seafile-server-${SEAFILE_VERSION}-server/

# plenty of patches
echo "diff --git a/tools/seafile-admin b/tools/seafile-admin
index 5e3658b..6cfeafd 100755
--- a/tools/seafile-admin
+++ b/tools/seafile-admin
@@ -518,10 +518,10 @@ def init_seahub():


 def check_django_version():
-    '''Requires django 1.8'''
+    '''Requires django >= 1.8'''
     import django
-    if django.VERSION[0] != 1 or django.VERSION[1] != 8:
-        error('Django 1.8 is required')
+    if django.VERSION[0] != 1 or django.VERSION[1] < 8:
+        error('Django 1.8+ is required')
     del django

" | patch -p1
# patch -p1 < /tmp/patches/001-seafile-server.patch

# official libevhtp requires seafile-server patching
if [[ "$LIBEVHTP_OFFICIAL" = "1" ]]; then
    patch -p1 < /tmp/patches/010-libevhtp-linking.patch
    patch -p1 < /tmp/patches/020-recent-libevhtp.patch
    patch -p1 < /tmp/patches/030-newer-libevhtp.patch
fi

./autogen.sh
./configure --with-mysql --with-postgresql --enable-python
make && make install

# Also copy scripts to save them
cp -r scripts/* "${SEAFILE_DIR}/seafile-server/"
mkdir -p "${SEAFILE_DIR}/seafile-server/runtime/"
mv "${SEAFILE_DIR}/seafile-server/seahub.conf" "${SEAFILE_DIR}/seafile-server/runtime/"
mkdir -p "${SEAFILE_DIR}/seafile-server/seafile/docs"
cp -rf "./doc/"seafile-tutorial* "${SEAFILE_DIR}/seafile-server/seafile/docs/"
chmod 755 "${SEAFILE_DIR}/seafile-server/" -R

cd $WORK_DIR/seafobj-${SEAFILE_VERSION}-server/
mv seafobj ${PYTHON_PACKAGES_DIR}/

cd $WORK_DIR/seafdav-${SEAFILE_VERSION}-server/
mv wsgidav ${PYTHON_PACKAGES_DIR}/

echo "export PYTHONPATH=${PYTHON_PACKAGES_DIR}:/usr/local/lib/python2.7/site-packages/:${SEAFILE_DIR}/seafile-server/seahub/thirdpart" >> /etc/profile.d/python-local.sh

ldconfig || true  # ldconfig exits with nonzero
echo "Seafile-Server has been built successfully!"

# Store seafile version, create symlinks to the actual data dir
echo -n "$SEAFILE_VERSION" > "${SEAFILE_DIR}/version"
chmod 755 "${SEAFILE_DIR}" -R
# create symlinks to user data dirs
symlinks=(conf ccnet seafile-data seahub-data)
for name in "${symlinks[@]}"; do
    ln -sf "${SEAFILE_DATA_DIR}/$name" "$SEAFILE_DIR/$name"
done

echo "Cleaning up temporary files..."
# Finally, cleanup
cd /
apk del --purge .build_dep
rm -rf $WORK_DIR
rm /var/cache/apk/*
rm -rf /root/.cache
rm -rf /tmp/*

echo "Done!"

