#!/usr/bin/env python3
"""
Container init script that checks whether seafile is properly configured and
runs the install / upgrade scripts if necessary.

Adapted from https://github.com/haiwen/seafile-docker/
"""

import re
import os
from os.path import dirname, join
from utils import setup_logging, get_install_dir, wait_for_mysql
from upgrade import check_upgrade
from bootstrap import init_seafile_server


SEAFILE_REPLACE_CONFIG = {
    "seahub_settings.py": {
        "SEAHUB_WEB_ROOT": [
            # need to edit many seahub options
            {"r": r"^SITE_ROOT\s*=.+$", "s": "SITE_ROOT = '{}'",
             "a": "SITE_ROOT = '{}'"},
            {"r": r"^LOGIN_URL\s*=.+$", "s": "LOGIN_URL = '{}accounts/login/'",
             "a": "LOGIN_URL = '{}accounts/login/'"},
            # {"r": r"^MEDIA_URL\s*=.+$", "s": "MEDIA_URL = '{}media/'",
            #  "a": "MEDIA_URL = '{}media/'"},
            # {"r": r"^COMPRESS_URL\s*=.+$", "s": "COMPRESS_URL = '{}media/'",
            #  "a": "COMPRESS_URL = '{}media/'"},
            # {"r": r"^STATIC_URL\s*=.+$", "s": "STATIC_URL = '{}media/assets/'",
            #  "a": "STATIC_URL = '{}media/assets/'"},
        ],
        "SEAFHTTP_URL": [
            {"r": r"^FILE_SERVER_ROOT\s*=.+$", "s": "FILE_SERVER_ROOT = '{}'",
             "a": "FILE_SERVER_ROOT = '{}'"},
        ],
    },
    "ccnet.conf": {
        "SEAFILE_URL": [
            {"r": r"^SERVICE_URL\s*=.+$", "s": "SERVICE_URL = {}" },
        ]
    },
}


def update_container_config():
    topdir = dirname(get_install_dir())
    for filename, vars in SEAFILE_REPLACE_CONFIG.items():
        full_path = join(topdir, 'conf', filename)
        lines = []
        with open(full_path, "r") as src:
            lines = src.read().splitlines() 
        changed = False
        new_lines = []
        for env_var, sed_arr in vars.items():
            if env_var not in os.environ:
                continue
            config_value = os.environ.get(env_var, None)
            if not isinstance(sed_arr, list):
                sed_arr = [sed_arr]
            for sed in sed_arr:
                new_lines = []
                found_var = False
                for line in lines:
                    new_line, found = re.subn(
                        sed["r"], sed["s"].format(config_value), line)
                    new_lines.append(new_line)
                    if found:
                        found_var = True
                        if new_line != line:
                            changed = True
                if not found_var and "a" in sed:
                    new_lines.append(sed["a"].format(config_value))
                    changed = True
                lines = new_lines
        if changed:
            # write the new file!
            with open(full_path, "w") as outf:
                outf.write("\n".join(lines) + "\n")


def main():
    wait_for_mysql()
    init_seafile_server()
    update_container_config()
    check_upgrade()


if __name__ == '__main__':
    setup_logging()
    main()

