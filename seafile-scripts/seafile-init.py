#!/usr/bin/env python3
"""
Container init script that checks whether seafile is properly configured and
runs the install / upgrade scripts if necessary.

Adapted from https://github.com/haiwen/seafile-docker/
"""

from utils import setup_logging
from upgrade import check_upgrade
from bootstrap import init_seafile_server


def main():
    init_seafile_server()
    check_upgrade()


if __name__ == '__main__':
    setup_logging()
    main()

