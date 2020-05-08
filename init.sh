#!/bin/bash

# Uncomment this to see debug output
#set -x
set -u -e -o pipefail

declare -r NC_COMMAND=nc
if ! type -t "$NC_COMMAND" >/dev/null 2>&1; then
	printf 'Please, install %s for network operations\n' "$NC_COMMAND"
	exit 1
fi

declare -r CURL_COMMAND=curl
if ! type -t "$CURL_COMMAND" >/dev/null 2>&1; then
	printf 'Please, install %s for http operations\n' "$CURL_COMMAND"
	exit 1
fi

declare -r TCP_TEST_COM="${NC_COMMAND} -z -w 2 \"\$1\" \"\$2\" >/dev/null 2>&1"
tcp_wait() {
	local space=
	printf 'Waiting for TCP %s:%s being available\n' "$1" "$2"
	while ! eval "$TCP_TEST_COM"; do
		printf '%s*' "$space"
		space=" "
		sleep 2s
	done
	printf '\nTCP %s:%s is ready\n' "$1" "$2"
	return 0
}

cd "$(dirname "$0")"

DOCKER_DOCROOT='/var/www/html'
HOST_DOCROOT="$(mktemp --tmpdir=/tmp -d 'docroot.XXXXXXX')"
chmod --silent 777 "$HOST_DOCROOT"
printf 'Created temporary docroot in %s\n' "$HOST_DOCROOT"

MARIADB_DOCKER_ID=
DOCKER_ID=
on_shutdown() {
	if test "$DOCKER_ID" != ""; then
		docker stop "$DOCKER_ID" >/dev/null 2>&1 || true
		DOCKER_ID=
	fi
	if test "$MARIADB_DOCKER_ID" != ""; then
		docker stop "$MARIADB_DOCKER_ID" >/dev/null 2>&1 || true
		MARIADB_DOCKER_ID=
	fi
	rm -r -f "$HOST_DOCROOT"
	HOST_DOCROOT=
}
trap on_shutdown EXIT

IMAGE_NAME='www-test-env'
HOST_NAME="${IMAGE_NAME}.local"
MODSECURITY_TARGZ='modsecurity-2.9.3.tar.gz'
MODSECURITY_BUILD_DIR='/modsecurity-build-root'
MODSECURITY_RULES_DIR='/modsecurity-rules'

_is_prune=0

help() {
	local prog="$(basename "$0")"

	printf 'Usage: %s [[-p|--prune] | [-h|--help]]\n' "$prog"
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
                     --build-arg="MODSECURITY_RULES_DIR=${MODSECURITY_RULES_DIR}" \
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
tcp_wait "$MARIADB_DOCKER_IP_ADDR" 3306

declare -a -r DOCKER_ARGV=(
	"docker"
	"run"
	"-d"
	"--mount"
	"\"type=bind,src=${HOST_DOCROOT},dst=${DOCKER_DOCROOT},bind-nonrecursive=true\""
	"-h"
	"\"$HOST_NAME\""
	"-w"
	"\"$DOCKER_DOCROOT\""
	"--rm"
	"-e"
	"\"WORDPRESS_DB_HOST=${MARIADB_DOCKER_IP_ADDR}\""
	"-e"
	"\"WORDPRESS_DB_USER=root\""
	"-e"
	"\"WORDPRESS_DB_PASSWORD=\""
	"-e"
	"\"WORDPRESS_DB_NAME=${MYSQL_DATABASE}\""
	"-e"
	"\"WORDPRESS_DB_CHARSET=utf8mb4\""
	"-e"
	"\"WORDPRESS_DB_COLLATE=utf8mb4_general_ci\""
	"\"${IMAGE_NAME}:latest\""
)

DOCKER_ID="$(eval "${DOCKER_ARGV[*]}")"
DOCKER_IP_ADDR="$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$DOCKER_ID")"

tcp_wait "$DOCKER_IP_ADDR" 80

# FIX ME
declare -r WP_TITLE="${IMAGE_NAME}"
declare -r WP_USER="root"
declare -r WP_PASS="root"
declare -r WP_EMAIL="webmaster@${HOST_NAME}"

declare -a -r WORDPRESS_POST_ARGS=(
	"\"weblog_title=${WP_TITLE}\""
	"\"user_name=${WP_USER}\""
	"\"admin_password=${WP_PASS}\""
	"\"admin_password2=${WP_PASS}\""
	"\"admin_email=${WP_EMAIL}\""
	"\"blog_public=0\""
)

WP_INST_CMD="${CURL_COMMAND} -s"
for v in "${WORDPRESS_POST_ARGS[@]}"; do
	WP_INST_CMD="${WP_INST_CMD} --data-urlencode ${v}"
done
WP_INST_CMD="${WP_INST_CMD} \"http://${DOCKER_IP_ADDR}/wp-admin/install.php?step=2\" >/dev/null 2>&1"
(
	printf 'Performing automated WordPress install...\n'
	space=
	eval "$WP_INST_CMD" &
	curl_pid="$!"
	while kill -n 0 "${curl_pid}" >/dev/null 2>&1; do
		printf '%s*' "$space"
		space=" "
		sleep 2s
	done
	wait "${curl_pid}"
	printf '\nWordPress installed!\n'
)

printf 'DONE! Log in to http://%s/wp-login.php using these credentials:\n' "$DOCKER_IP_ADDR"
printf '    USERNAME: %s\n' "$WP_USER"
printf '    PASSWORD: %s\n' "$WP_PASS"
printf '\n'

printf 'LOGS:\n'
docker container logs --follow "$DOCKER_ID"

exit 0
