#include <stdio.h>
#include <string.h>

#include <unistd.h>
#include <signal.h>

#include "log.h"
#include "process.h"

static void sighup_action(int sig, siginfo_t *info, void *ucontext)
{
	(void) sig;
	(void) ucontext;
	app_log(lvl_info, "Received SIGHUP from %d\n", (int) info->si_pid);
}

int main(int argc, char **argv)
{
	struct sigaction act;

	(void) argc;

	if (app_init_logs("-", lvl_debug) < 0) {
		fprintf(stderr,
		        "%s: failed to initialize logs\n",
		        argv[0]);
		_exit(1);
	}

	if (daemonize() < 0)
		_exit(1);

	memset(&act, 0, sizeof(act));
	sigemptyset(&act.sa_mask);
	act.sa_flags = SA_SIGINFO;
	act.sa_sigaction = sighup_action;

	sigaction(SIGHUP, &act, (struct sigaction *) 0);

	for (;;)
		pause();
}
