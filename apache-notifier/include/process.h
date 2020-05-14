#ifndef _PROCESS_H
#define _PROCESS_H

typedef void fork_handler_t(long);
int xfork(fork_handler_t *parent, fork_handler_t *child);
int daemonize(void);

#endif
