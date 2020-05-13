#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/inotify.h>
#include <fcntl.h>
#include <unistd.h>
#include <getopt.h>
#include <signal.h>
#include <poll.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "log.h"
#include "process.h"

static int fs_watcher_get_handle(const char *path)
{
	int ifd;

	ifd = inotify_init();
	if (ifd < 0)
		return -1;

	if (inotify_add_watch(ifd, path, IN_CREATE |
	                                 IN_MODIFY |
	                                 IN_DELETE |
	                                 IN_MOVED_FROM |
	                                 IN_MOVED_TO |
	                                 IN_ONLYDIR |
	                                 IN_EXCL_UNLINK) < 0) {
		app_log(lvl_err,
		        "%s: inotify_add_watch(%d, %s) failed\n",
		        __func__,
		        ifd,
		        path);
		(void) close(ifd);
		return -1;
	}

	return ifd;
}

static void fs_watcher_callback(int fd, void *arg)
{
#define BUF_ALGN __attribute__((aligned(__alignof__(struct inotify_event))))
	unsigned char buf[1 << 12] BUF_ALGN, *bufp;
#undef BUF_ALGN
	char msg[1 << 12], *msgp;
	const struct inotify_event *evt;
	long nr_read, apache_pid;

	apache_pid = (long) ((unsigned long) arg);

	while (1) {
		nr_read = read(fd, buf, sizeof(buf));
		if (nr_read < 0 && errno != EAGAIN) {
			app_log(lvl_err,
			        "%s: read(%d, %p, %u) failed\n",
			        __func__,
			        fd,
			        buf,
			        sizeof(buf));
			_exit(1);
		}

		if (nr_read <= 0)
			break;

		msgp = msg;
		msgp[0] = '\0';

		for (bufp = buf; bufp < &buf[nr_read];) {
			evt = (const struct inotify_event *) bufp;
			bufp += (sizeof(struct inotify_event) + evt->len);

			if (evt->len) {
				unsigned int namelen;
				char *namepos;

				namelen = strlen(evt->name);
				namepos = strstr(msg, evt->name);
				if (namepos &&
				    (namepos[namelen] == '\0' || namepos[namelen] == ' ')) {
					
					app_log(lvl_debug, "%s: %s found in \"%s\"\n",
					        __func__, evt->name, msg);
					continue;
				}

				if (msgp >= &msg[sizeof(msg)]) {
					app_log(lvl_debug, "%s: ignoring %s because \"%s\" is full\n",
					        __func__, evt->name, msg);
					continue;
				}

				if (msgp != msg)
					*(msgp++) = ' ';

				{
					unsigned int copysz;

					copysz = (unsigned int) (&msg[sizeof(msg)] - msgp);
					if (copysz > namelen)
						copysz = namelen;
					msgp = mempcpy(msgp, evt->name, copysz);
					if (msgp < &msg[sizeof(msg)])
						*msgp = '\0';
					else
						msg[sizeof(msg) - 1] = '\0';
				}
			}
		}

		if (msgp != msg) {
			app_log(lvl_info,
			        "%s: altered files [%s], sending signal to PID #%ld\n",
			        __func__,
			        msg,
			        apache_pid);

			/* From APACHE httpd docs [https://httpd.apache.org/docs/2.4/stopping.html]:
			   ```
			     As with a graceful restart,
			     a syntax check is run before the restart is attempted.
			     If your configuration file has errors in it,
			     the restart will not be attempted,
			     and you will receive notification of the syntax error(s).
			   ```
			   So there is no point in spawning another httpd instance
			   to check config correctness. */
			if (kill(apache_pid, SIGHUP) < 0) {
				app_log(lvl_err,
				        "%s: kill(%ld, SIGHUP) failed\n",
				        __func__,
				        apache_pid);
				_exit(1);
			}
		}
	}
}

typedef void handler_t(int, void *);
struct files {
	int fd;
	handler_t *func;
	void *arg;
};

static void __attribute__((noreturn)) main_loop(const struct files *elems, unsigned int nr_elems)
{
	struct pollfd *poll_data;
	int poll_nr_avail;
	unsigned int i;

	poll_data = malloc(sizeof(*poll_data) * nr_elems);
	if (!poll_data) {
		app_log(lvl_err,
		        "%s: malloc() failed\n",
		        __func__);
		_exit(1);
	}

	for (i = 0; i < nr_elems; ++i) {
		int flags;

		poll_data[i].fd = elems[i].fd;
		poll_data[i].events = POLLIN;

		/* Force non-blocking operation on filedes &
		   also check if given filedes exists */
		if ((flags = fcntl(elems[i].fd, F_GETFL)) < 0) {
			app_log(lvl_err,
			        "%s: fcntl(%d, F_GETFL) failed\n",
			        __func__,
			        elems[i].fd);
			_exit(1);
		}
		if (fcntl(elems[i].fd, F_SETFL, (flags | O_NONBLOCK)) < 0) {
			app_log(lvl_err,
			        "%s: fcntl(%d, F_SETFL) failed\n",
			        __func__,
			        elems[i].fd);
			_exit(1);
		}
	}

	while (1) {
		poll_nr_avail = poll(poll_data, nr_elems, -1);
		if (poll_nr_avail < 0) {
			app_log(lvl_err,
			        "%s: poll() failed\n",
			        __func__);
			_exit(1);
		}

		if (poll_nr_avail > 0) {
			for (i = 0; i < nr_elems; ++i) {
				if (poll_data[i].revents & POLLIN)
					elems[i].func(elems[i].fd, elems[i].arg);
			}
		}
	}
}

#define LONG_OPT_ENTRY(__name, __has_arg, __val) \
{ .name = __name, .has_arg = __has_arg, .flag = NULL, .val = __val, }

static struct option _long_options[] = {
	LONG_OPT_ENTRY("logs", 1, 'l'),
	LONG_OPT_ENTRY("verbose", 0, 'v'),
	LONG_OPT_ENTRY("silent", 0, 's'),
	LONG_OPT_ENTRY("pid", 1, 'p'),
	LONG_OPT_ENTRY(NULL, 0, '\0'),
};

#undef LONG_OPT_ENTRY

static inline int safe_atol(const char *ascii, long *valp)
{
	long val;
	char *endp;

	/* Invalid data */
	if (!ascii || *ascii == '\0')
		return -1;

	endp = NULL;
	errno = 0;
	val = strtol(ascii, &endp, 0);

	/* Range error */
	if (errno)
		return -1;
	/* Invalid characters */
	if (endp && *endp != '\0')
		return -1;

	*valp = val;
	return 0;
}

static void _daemonize(long pid)
{
	if (pid) {
		app_log(lvl_info,
		        "%s: daemon PID = #%ld\n",
		        __func__,
		        pid);
		_exit(0);
	} else {
		int fd;

		(void) setsid();
		fd = open("/dev/null", O_RDWR);
		if (fd < 0)
			return;
		(void) dup2(fd, STDIN_FILENO);
		(void) dup2(fd, STDOUT_FILENO);
		/* We use STDERR_FILENO for logs */
		(void) close(fd);
	}
}

static void daemonize(void)
{
	if (xfork(_daemonize, _daemonize) < 0) {
		_exit(1);
	}
}

int main(int argc, char **argv)
{
	int c;
	const char *log_file = NULL, *tracked_path;
	long apache_pid = -1;
	enum log_levels lvl;
	struct files _data;

	lvl = lvl_info;
	app_set_lvl(lvl);

	while ((c = getopt_long(argc, argv, ":l:vsp:", _long_options, NULL)) != -1) {
		switch (c) {
		case 'l':
			log_file = optarg;
			break;
		case 'v':
			--lvl;
			lvl = app_set_lvl(lvl);
			break;
		case 's':
			++lvl;
			lvl = app_set_lvl(lvl);
			break;
		case 'p':
			(void) safe_atol(optarg, &apache_pid);

			if (apache_pid <= 0) {
				app_log(lvl_err,
				        "%s: invalid PID\n",
				        __func__);
				_exit(1);
			}

			if (kill(apache_pid, 0) < 0) {
				app_log(lvl_err,
				        "%s: PID [%ld]\n",
				        __func__,
				        apache_pid);
				_exit(1);
			}

			break;
		default:
			app_log(lvl_err,
			        "%s: parsing error\n",
			        __func__);
			_exit(1);
		}
	}

	if (optind + 1 != argc) {
		app_log(lvl_err,
		        "%s: no tracked path found in arguments\n",
		        __func__);
		_exit(1);
	}
	tracked_path = argv[optind];

	if (log_file) {
		if (app_redirect_logs(log_file) < 0) {
			app_log(lvl_err,
			        "%s: failed to redirect logs to %s\n",
			        __func__,
			        log_file);
			_exit(1);
		}
	}

	daemonize();

	_data.fd = fs_watcher_get_handle(tracked_path);
	_data.func = fs_watcher_callback;
	_data.arg = (void *) ((unsigned long) apache_pid);

	if (_data.fd < 0)
		_exit(1);

	main_loop(&_data, 1);
}