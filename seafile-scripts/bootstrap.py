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
    call, get_conf, get_install_dir, loginfo, get_script, get_seafile_version,
    update_version_stamp, wait_for_mysql
)

seafile_version = get_seafile_version()
installdir = get_install_dir()
topdir = dirname(installdir)
data_dir = '/var/lib/seafile'


def init_seafile_server():
    if exists(join(topdir, 'conf', 'seafile.conf')):
        loginfo('Skip running setup-seafile-mysql.py because there is existing config.')
        return

    loginfo('Running setup-seafile-mysql.py in auto mode.')
    env = {
        'SERVER_NAME': get_conf('SEAFILE_SERVER_NAME', "Seafile"),
        'SERVER_IP': get_conf('SEAFILE_SERVER_IP', 'seafile.example.com'),
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
    
    # create the required data volume directories
    def mkdirp(path):
        if not os.path.exists(path):
            os.mkdir(path)

    # remove symlinks to data (seafile scripts want to create them themselves)
    os.unlink(join(topdir, 'conf'))
    os.unlink(join(topdir, 'ccnet'))
    os.unlink(join(topdir, 'seafile-data'))
    os.unlink(join(topdir, 'seahub-data'))
    # bin dir
    os.symlink("/usr/local/bin", join(installdir, "seafile", "bin"))

    # Change the script to disable check MYSQL_USER_HOST
    call('''sed -i -e '/def validate_mysql_user_host(self, host)/a \ \ \ \ \ \ \ \ return host' {}'''
        .format(get_script('setup-seafile-mysql.py')))
    call('''sed -i -e '/def validate_mysql_host(self, host)/a \ \ \ \ \ \ \ \ return host' {}'''
        .format(get_script('setup-seafile-mysql.py')))
    # run the script
    setup_script = get_script('setup-seafile-mysql.sh')

    wait_for_mysql()
    call('{} auto -n seafile'.format(setup_script), env=env)

    seafile_server_root = get_conf('SEAFHTTP_URL', 'https://seafile.example.com/seafhttp')
    with open(join(topdir, 'conf', 'seahub_settings.py'), 'a+') as fp:
        fp.write('\n')
        fp.write("TIME_ZONE = '{time_zone}'".format(time_zone=os.getenv('TZ', default='Etc/UTC')))
        fp.write('\n')
        fp.write('FILE_SERVER_ROOT = "{seafile_server_root}"'.format(seafile_server_root=seafile_server_root))
        fp.write('\n')

    # Change the unix socket file path to "/opt/seafile/ccnet.sock".
    with open(join(topdir, 'conf', 'ccnet.conf'), 'a+') as fp:
        fp.write('\n')
        fp.write('[Client]\n')
        fp.write('UNIX_SOCKET = /opt/seafile/ccnet.sock\n')
        fp.write('\n')

    # move the data directories to the volume and re-create the symlinks
    for dir in ('conf', 'ccnet', 'seafile-data', 'seahub-data'):
        os.rename(join(topdir, dir), join(data_dir, dir))
        os.symlink(join(data_dir, dir), join(topdir, dir))

    loginfo('Updating version stamp')
    update_version_stamp(seafile_version)

