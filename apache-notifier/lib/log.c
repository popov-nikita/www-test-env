#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>

#include "log.h"

static int _app_log_fd = -1;
static enum log_levels _app_log_lvl = lvl_info;
static const char *_app_exe_name = (char *) 0;

#define LVL_MAP_ENTRY(__lvl__) [lvl_##__lvl__] = "(" #__lvl__ ")"
static const char *_lvl_map[] = {
	LVL_MAP_ENTRY(debug),
	LVL_MAP_ENTRY(info),
	LVL_MAP_ENTRY(warn),
	LVL_MAP_ENTRY(err),
};
#undef LVL_MAP_ENTRY

static inline enum log_levels clamp_lvl(enum log_levels lvl)
{
	if (lvl < _LVL_INIT)
		lvl = _LVL_INIT;
	else if (lvl >= _NR_LVLS)
		lvl = _NR_LVLS - 1;

	return lvl;
}

/* Must be called before daemonization */
int app_init_logs(const char *path, enum log_levels log_lvl)
{
	int log_fd, rc, flags;
	static char exe_name_buf[1024];
	char *exe_name;
	long nr_stored;

	rc = -1;

	if (!path)
		goto ret;

	/* "" and "-" are for standard error stream */
	if ((path[0] == '\0'))
		path = "-";

	if ((path[0] == '-') &&
	    (path[1] == '\0')) {
		log_fd = dup(STDERR_FILENO);
	} else {
		log_fd = open(path, O_CREAT | O_WRONLY | O_APPEND, S_IRUSR | S_IWUSR);
	}

	if (log_fd < 0)
		goto ret;

	/* Ensure log filedes is closed upon successful execve() */
	if ((flags = fcntl(log_fd, F_GETFD)) < 0)
		goto ret_close;
	if (fcntl(log_fd, F_SETFD, (flags | FD_CLOEXEC)) < 0)
		goto ret_close;

	/* Obtain pretty executable name, so we print it in log entries */
	nr_stored = readlink("/proc/self/exe", exe_name_buf, sizeof(exe_name_buf));
	if ((nr_stored < 0) ||
	    (nr_stored == ((long) sizeof(exe_name_buf))))
		goto ret_close;
	exe_name_buf[nr_stored] = '\0';

	exe_name = strrchr(exe_name_buf, '/');
	if (exe_name)
		exe_name++;
	else
		exe_name = exe_name_buf;

	_app_exe_name = exe_name;
	_app_log_lvl = clamp_lvl(log_lvl);
	_app_log_fd = log_fd;
	rc = 0;

ret_close:
	if (rc) {
		(void) close(log_fd);
	}
ret:
	return rc;
}

/* <APP name> at <GMT date> [PID #<number>] (<severity>) <msg> */
static void _app_log(const char *label, const char *fmt, va_list ap)
{
	time_t ts;
	struct tm tm;
	char msg[4096], *msgp;
	int pid;

	ts = time((time_t *) 0);
	if (ts == ((time_t) -1))
		return;

	msgp = stpcpy(msg, _app_exe_name);
	msgp = stpcpy(msgp, " at ");

	gmtime_r(&ts, &tm);
	asctime_r(&tm, msgp);
	msgp += strlen(msgp);
	if (msgp[-1] == '\n')
		--msgp;
	*(msgp++) = ' ';

	pid = (int) getpid();
	msgp += snprintf(msgp,
	                 (sizeof(msg) - (unsigned long) (msgp - msg)),
	                 "[PID #%d] %s ",
	                 pid,
	                 label);

	msgp += vsnprintf(msgp,
	                  (sizeof(msg) - (unsigned long) (msgp - msg)),
	                  fmt,
	                  ap);

	(void) write(_app_log_fd, msg, strlen(msg));
}

void app_log(enum log_levels lvl, const char *fmt, ...)
{
	va_list ap;
	int saved_errno = errno;

	lvl = clamp_lvl(lvl);
	va_start(ap, fmt);
	if ((lvl >= _app_log_lvl) &&
	    (_app_log_fd >= 0)) {
		_app_log(_lvl_map[lvl], fmt, ap);
	}
	va_end(ap);

	errno = saved_errno;
}
