#!/bin/bash
# Seafile build script for Alpine Linux
# Forked from https://github.com/VGoshev/seafile-docker

set -e
set -x

ln -s /etc/profile.d/color_prompt /etc/profile.d/color_prompt.sh
PATH="${PATH}:/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/usr/local/sbin"

# Destination dir for the Seafile installation
SEAFILE_HOME=${SEAFILE_HOME:-/home/seafile}

# Seafile Version
SEAFILE_VERSION="${SEAFILE_VERSION:-unknown}"

[ -z $LIBEVHTP_VERSION  ] && LIBEVHTP_VERSION="1.2.18"
#[ -z $LIBEVHTP_VERSION  ] && LIBEVHTP_VERSION="18c649203f009ef1d77d6f8301eba09af3777adf"
[ -z $LIBSEARPC_VERSION ] && LIBSEARPC_VERSION="3.1-latest"

# Use a temporary dir for all our work
WORK_DIR="/tmp/seafile"
mkdir -p $WORK_DIR
cd $WORK_DIR

PYTHON_PACKAGES_DIR=`python -c "from distutils.sysconfig import get_python_lib; print(get_python_lib())"`

## Download & compile Seafile & components
## ==============================================================

# Download & compile libevhtp

#wget -nv https://github.com/ellzey/libevhtp/archive/${LIBEVHTP_VERSION}.tar.gz -O- | tar xzf -
wget -nv https://github.com/criticalstack/libevhtp/archive/${LIBEVHTP_VERSION}.tar.gz -O- | tar xzf -
#https://github.com/haiwen/libevhtp/archive/18c649203f009ef1d77d6f8301eba09af3777adf.zip
cd libevhtp-${LIBEVHTP_VERSION}/

ls -l /tmp/patches/901-openssl-thread.patch
patch -p1 < /tmp/patches/901-openssl-thread.patch

cmake .  ## -DEVHTP_DISABLE_SSL=ON -DEVHTP_BUILD_SHARED=ON .
make && make install
sed -i 's,^\(include\|lib\)dir=,\0/usr/local/\1,' "/usr/local/lib/pkgconfig/evhtp.pc"
# WORKAROUND: fix pkgconfig paths (make installs them wrong)
cat "/usr/local/lib/pkgconfig/evhtp.pc"

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

#mv $WORK_DIR/seahub-${SEAFILE_VERSION}-server/ /usr/local/share/seahub
mkdir -p /usr/local/share/seafile
tar czf /usr/local/share/seafile/seahub.tgz -C $WORK_DIR/seahub-${SEAFILE_VERSION}-server/ ./

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

# As a First step we need to patch it
cd $WORK_DIR/seafile-server-${SEAFILE_VERSION}-server/

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

patch -p1 < /tmp/patches/001-seafile-server.patch
patch -p1 < /tmp/patches/010-libevhtp-linking.patch
patch -p1 < /tmp/patches/020-recent-libevhtp.patch
patch -p1 < /tmp/patches/030-newer-libevhtp.patch

./autogen.sh
./configure --with-mysql --with-postgresql --enable-python
make && make install

# Copy some useful scripts to /usr/local/bin

#mkdir -p /usr/local/bin
cp scripts/seaf-fsck.sh /usr/local/bin/seafile-fsck
cp scripts/seaf-gc.sh /usr/local/bin/seafile-gc
# Also copy scripts to save them
#mkdir -p /usr/local/share/seafile/
mv scripts /usr/local/share/seafile/

cd $WORK_DIR/seafobj-${SEAFILE_VERSION}-server/
mv seafobj ${PYTHON_PACKAGES_DIR}/

cd $WORK_DIR/seafdav-${SEAFILE_VERSION}-server/
mv wsgidav ${PYTHON_PACKAGES_DIR}/

echo "export PYTHONPATH=${PYTHON_PACKAGES_DIR}:/usr/local/lib/python2.7/site-packages/:${SEAFILE_HOME}/seafile-server/seahub/thirdpart" >> /etc/profile.d/python-local.sh

ldconfig || true

echo "Seafile-Server has been built successfully!"

# Install preparations

addgroup -g "$SEAFILE_UID" seafile
adduser -D -s /bin/sh -g "Seafile Server" -G seafile -h "$SEAFILE_HOME" -u "$SEAFILE_UID" seafile

# Create seafile-server dir 
su - -c "mkdir ${SEAFILE_HOME}/seafile-server" seafile

# Store seafile version
# Store seafile version and if tis is edge image
mkdir -p /var/lib/seafile
echo -n "$SEAFILE_VERSION" > /var/lib/seafile/version

echo "The seafile user has been created and configured successfully!"

echo "Cleaning up temporary files..."

# Finally, cleanup
cd /
apk del --purge .build_dep
rm -rf $WORK_DIR
rm /var/cache/apk/*
rm -rf /root/.cache
rm -rf /tmp/*

echo "Done!"

