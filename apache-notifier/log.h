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
	lvl_crit,
	_NR_LVLS,
};

enum log_levels app_set_lvl(enum log_levels lvl);
int app_redirect_logs(const char *path);
void app_log(enum log_levels lvl, const char *fmt, ...);

#endif
