#!/usr/bin/env python
"""
Seafile initialization script.

Adapted from https://github.com/haiwen/seafile-docker/
"""

import argparse
import os
from os.path import abspath, basename, exists, dirname, join, isdir
import shutil
import sys
import uuid
import time

from utils import (
    call, get_conf, get_install_dir, loginfo,
    get_script, get_seafile_version,
    update_version_stamp
)


seafile_version = get_seafile_version()
installdir = get_install_dir()
topdir = dirname(installdir)
data_dir = '/var/lib/seafile'


def init_seafile_server():
    if exists(join(topdir, 'conf', 'seafile.conf')):
        loginfo('Skip seafile-init because there is existing config.')
        return

    loginfo('Running setup-seafile-mysql.py in auto mode.')
    env = {
        'SERVER_NAME': get_conf('SEAFILE_SERVER_NAME', "seafile"),
        'SERVER_IP': get_conf('SEAFILE_SERVER_HOSTNAME', 'seafile.example.com'),
        'CCNET_DB': get_conf('CCNET_DB', 'seafile_ccnet'),
        'SEAFILE_DB': get_conf('SEAFILE_DB', 'seafile_db'),
        'SEAHUB_DB': get_conf('SEAHUB_DB', 'seafile_hub'),
        'MYSQL_HOST': get_conf('DB_HOST', 'mysql'),
        'MYSQL_PORT': get_conf('DB_PORT', '3306'),
        'MYSQL_USER': get_conf('DB_USER', 'seafile'),
        'MYSQL_USER_PASSWD': get_conf('DB_PASS', ''),
        'MYSQL_USER_HOST': '%',
        'USE_EXISTING_DB': get_conf('DB_EXISTING', '1'),
        'MYSQL_ROOT_PASSWD': get_conf('DB_ROOT_PASS', ''),
    }

    # Change the script to disable check MYSQL_USER_HOST
    call('''sed -i -e '/def validate_mysql_user_host(self, host)/a \\ \\ \\ \\ \\ \\ \\ \\ return host' {}'''
        .format(get_script('setup-seafile-mysql.py')))

    call('''sed -i -e '/def validate_mysql_host(self, host)/a \\ \\ \\ \\ \\ \\ \\ \\ return host' {}'''
        .format(get_script('setup-seafile-mysql.py')))

    # run the setup script
    call('{} auto -n seafile'.format(get_script('setup-seafile-mysql.sh')), env=env)

    seafile_server_root = get_conf('SEAFHTTP_URL', 'https://seafile.example.com/seafhttp')
    with open(join(topdir, 'conf', 'seahub_settings.py'), 'a+') as fp:
        fp.write('\n')
        CACHE_STR = """CACHES = {
    'default': {
        'BACKEND': 'django_pylibmc.memcached.PyLibMCCache',
        'LOCATION': 'memcached:11211',
    },
    'locmem': {
        'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
    },
}
COMPRESS_CACHE_BACKEND = 'locmem'"""
        # fp.write(CACHE_STR)
        # fp.write('\n')
        fp.write("TIME_ZONE = '{time_zone}'".format(time_zone=os.getenv('TZ',default='Etc/UTC')))
        fp.write('\n')
        fp.write('FILE_SERVER_ROOT = "{seafhttp_url}"'.format(seafhttp_url=seafile_server_root))
        fp.write('\n')

    # By default ccnet-server binds to the unix socket file
    # "/opt/seafile/ccnet/ccnet.sock", but /opt/seafile/ccnet/ is a mounted
    # volume from the docker host, and on windows and some linux environment
    # it's not possible to create unix sockets in an external-mounted
    # directories. So we change the unix socket file path to
    # "/opt/seafile/ccnet.sock" to avoid this problem.
    with open(join(topdir, 'conf', 'ccnet.conf'), 'a+') as fp:
        fp.write('\n')
        fp.write('[Client]\n')
        fp.write('UNIX_SOCKET = /opt/seafile/ccnet.sock\n')
        fp.write('\n')

    # Modify seafdav config
    if os.path.exists(join(topdir, 'conf', 'seafdav.conf')):
        with open(join(topdir, 'conf', 'seafdav.conf'), 'r') as fp:
            fp_lines = fp.readlines()
            if 'share_name = /\n' in fp_lines:
               replace_index = fp_lines.index('share_name = /\n')
               replace_line = 'share_name = /seafdav\n'
               fp_lines[replace_index] = replace_line
        with open(join(topdir, 'conf', 'seafdav.conf'), 'w') as fp:
            fp.writelines(fp_lines)

    # move the data directories to the volume and re-create the symlinks
    for dir in ('conf', 'logs', 'ccnet', 'seafile-data', 'seahub-data'):
        src = join(topdir, dir)
        dst = join(data_dir, dir)
        if not exists(dst) and exists(src):
            shutil.move(src, data_dir)
            os.symlink(dst, src)

    loginfo('Updating version stamp')
    update_version_stamp(seafile_version)

