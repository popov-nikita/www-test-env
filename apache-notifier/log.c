#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

#include "log.h"

static enum log_levels _app_lvl = lvl_info;

#define LVL_MAP_ENTRY(__lvl__) [lvl_##__lvl__] = #__lvl__
static const char *_lvl_map[] = {
	LVL_MAP_ENTRY(debug),
	LVL_MAP_ENTRY(info),
	LVL_MAP_ENTRY(warn),
	LVL_MAP_ENTRY(err),
	LVL_MAP_ENTRY(crit),
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

enum log_levels app_set_lvl(enum log_levels lvl)
{
	lvl = clamp_lvl(lvl);

	_app_lvl = lvl;

	return lvl;
}

int app_redirect_logs(const char *path)
{
	int rc, fd;
	int saved_errno = 0;

	rc = -1;
	fd = open(path, O_CREAT | O_WRONLY | O_APPEND, S_IRUSR | S_IWUSR);
	if (fd < 0) {
		saved_errno = errno;
		goto ret;
	}

	if (dup2(fd, STDERR_FILENO) < 0) {
		saved_errno = errno;
		goto ret_close;
	}

	rc = 0;

ret_close:
	(void) close(fd);
	if (rc)
		errno = saved_errno;
ret:
	return rc;
}

void app_log(enum log_levels lvl, const char *fmt, ...)
{
	va_list ap;
	int saved_errno = errno;

	va_start(ap, fmt);
	lvl = clamp_lvl(lvl);
	if (lvl >= _app_lvl) {
		const char *err_msg = (const char *) 0;
		if (lvl >= lvl_err)
			err_msg = saved_errno ? strerror(saved_errno) : "No error";

		if (err_msg)
			dprintf(STDERR_FILENO, "@%s:\t [%s]\t ", _lvl_map[lvl], err_msg);
		else
			dprintf(STDERR_FILENO, "@%s:\t ", _lvl_map[lvl]);

		vdprintf(STDERR_FILENO, fmt, ap);
	}
	va_end(ap);

	/* Can't continue */
	if (lvl == lvl_crit)
		_exit(1);

	errno = saved_errno;
}
