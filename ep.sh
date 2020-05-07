#!/bin/bash

# Uncomment this to see debug output
#set -x
set -u -e -o pipefail

# Copy files so it is possible to handle them from host
umask 0000
cp -R --no-preserve=all -t . /usr/src/wordpress/*
chown -R "$(stat -c '%U:%G' /usr/src/wordpress/index.php)" *

#exec bash
exec docker-entrypoint.sh apache2-foreground -k start
