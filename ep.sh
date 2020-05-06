#!/bin/bash

set -x
set -u -e -o pipefail

# Copy files so it is possible to handle them from host
umask 0000
cp -R --no-preserve=all -t . /usr/src/wordpress/*
chown -R "$(stat -c '%U:%G' /usr/src/wordpress/index.php)" *

exec -c sh
exec -c docker-entrypoint.sh apache2-foreground -k start
