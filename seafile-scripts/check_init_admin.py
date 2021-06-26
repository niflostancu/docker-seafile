#!/usr/bin/env python3
"""
Checks whether the admin user exists and creates it if the environment variables
are set.
"""

import os
import importlib.util
from os.path import join
from utils import get_install_dir


def check_create_admin():
    if ("SEAFILE_ADMIN_EMAIL" not in os.environ) or (
            "SEAFILE_ADMIN_PASSWORD" not in os.environ):
        return
    spec = importlib.util.spec_from_file_location(
        "seafile_server.check_init_admin",
        join(get_install_dir(), "check_init_admin.py"))
    chkinitadmin = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(chkinitadmin)
    if not chkinitadmin.need_create_admin():
        return
    chkinitadmin.create_admin(os.environ["SEAFILE_ADMIN_EMAIL"],
                              os.environ["SEAFILE_ADMIN_PASSWORD"])


def main():
    check_create_admin()


if __name__ == '__main__':
    main()

