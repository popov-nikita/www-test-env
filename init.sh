#!/bin/bash

set -x
set -u -e -o pipefail

cd "$(dirname "$0")"

DOCKER_DOCROOT='/var/www/html'
HOST_DOCROOT="$(mktemp --tmpdir=/tmp -d 'docroot.XXXXXXX')"
chmod --silent 777 "$HOST_DOCROOT"
printf 'Created temporary docroot in %s\n' "$HOST_DOCROOT"

remove_temp_docroot() {
	rm -r -f "$HOST_DOCROOT"
}
trap remove_temp_docroot EXIT

IMAGE_NAME='www-test-env'
HOST_NAME="${IMAGE_NAME}.local"
MODSECURITY_TARGZ='modsecurity-2.9.3.tar.gz'
MODSECURITY_BUILD_DIR='/modsecurity-build-root'

_is_prune=0
_it_opts=

help() {
	local prog="$(basename "$0")"

	printf 'Usage: %s [[-i|--interactive] [-p|--prune] | [-h|--help]]\n' "$prog"
	printf '       -i|--interactive    Attach pseudo TTY to STDIN of this container\n'
	printf '       -p|--prune          Remove existing image and rebuild it from scratch\n'
	printf '       -h|--help           Show this message\n'

	exit 1
}

while test $# -gt 0; do
	case "$1" in
	-p|--prune)
		if test "$(docker images -q "${IMAGE_NAME}:latest")" != ""; then
			_is_prune=1
		fi
		;;
	-i|--interactive)
		_it_opts='-i -t'
		;;
	-h|--help)
		help
		;;
	*)
		printf 'Unknown option: %s\n' "$1"
		exit 1
		;;
	esac
	shift
done

if test $_is_prune -eq 1; then
	docker rmi -f "${IMAGE_NAME}:latest"
fi

if test "$(docker images -q "${IMAGE_NAME}:latest")" = ""; then
	docker build --build-arg="MODSECURITY_TARGZ=${MODSECURITY_TARGZ}" \
	             --build-arg="MODSECURITY_BUILD_DIR=${MODSECURITY_BUILD_DIR}" \
	             -t "${IMAGE_NAME}:latest" .
fi

MYSQL_ROOT_PASSWORD=
MYSQL_DATABASE="$IMAGE_NAME"

declare -r MARIADB_IMAGE_NAME='mariadb'
if test "$(docker images -q "${MARIADB_IMAGE_NAME}:latest")" = ""; then
	docker image pull "${MARIADB_IMAGE_NAME}:latest"
fi

declare -a -r MARIADB_DOCKER_ARGV=(
	"docker"
	"run"
	"-d"
	"--rm"
	"-e"
	"\"MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}\""
	"-e"
	"\"MYSQL_DATABASE=${MYSQL_DATABASE}\""
	"-e"
	"\"MYSQL_ALLOW_EMPTY_PASSWORD=yes\""
	"\"${MARIADB_IMAGE_NAME}:latest\""
	"--character-set-server=utf8mb4"
	"--collation-server=utf8mb4_general_ci"
)

MARIADB_DOCKER_ID="$(eval "${MARIADB_DOCKER_ARGV[*]}")"
MARIADB_DOCKER_IP_ADDR="$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$MARIADB_DOCKER_ID")"

# MariaDB server takes too long to start-up. Need to wait here before we can proceed.
# See: https://hub.docker.com/_/mariadb:
# If there is no database initialized when the container starts,
# then a default database will be created.
# While this is the expected behavior,
# this means that it will not accept incoming connections until such initialization completes.
# This may cause issues when using automation tools,
# such as docker-compose, which start several containers simultaneously.
printf 'Waiting for %s:3306 being available\n' "$MARIADB_DOCKER_IP_ADDR"
while ! (read -N 1 -r -s < "/dev/tcp/${MARIADB_DOCKER_IP_ADDR}/3306") >/dev/null 2>&1; do
	printf 'Waiting...\n'
	sleep 1s
done

exit 0

declare -a -r DOCKER_ARGV=(
	"docker"
	"run"
	"$_it_opts"
	"--mount"
	"\"type=bind,src=${HOST_DOCROOT},dst=${DOCKER_DOCROOT},bind-nonrecursive=true\""
	"-h"
	"\"$HOST_NAME\""
	"-w"
	"\"$DOCKER_DOCROOT\""
	"--rm"
	"\"${IMAGE_NAME}:latest\""
)

eval "${DOCKER_ARGV[*]}"

exit 0
