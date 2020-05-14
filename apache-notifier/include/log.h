#ifndef _LOG_H
#define _LOG_H

enum log_levels {
	/* Force this enum to be signed integer type */
	__lvl_dummy = -1,
	_LVL_INIT = 0,
	lvl_debug = _LVL_INIT,
	lvl_info,
	lvl_warn,
	lvl_err,
	_NR_LVLS,
};

/* Must be called before daemonization */
int app_init_logs(const char *path, enum log_levels log_lvl);
void app_log(enum log_levels lvl, const char *fmt, ...);

#endif
