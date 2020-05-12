#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#include <semaphore.h>

#include "log.h"
#include "process.h"

static void *mmap_shmem(unsigned long size)
{
	void *p;

	p = mmap((void *) 0, size, PROT_WRITE | PROT_READ, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
	if (p == MAP_FAILED) {
		app_log(lvl_err,
		        "%s: mmap() failed\n",
		        __func__);
		p = NULL;
	}

	return p;
}

/* This extended version of fork() ensures that child's handler
   is executed before parent's handler */
int xfork(fork_handler_t *parent, fork_handler_t *child)
{
	int rc;
	long pid;
	sem_t *s;

	rc = -1;

	s = mmap_shmem(sizeof(*s));
	if (!s)
		goto ret;

	if (sem_init(s, 1, 0) < 0) {
		app_log(lvl_err,
		        "%s: sem_init(%p, 1, 0) failed\n",
		        __func__,
		        s);
		goto ret_unmap;
	}

	pid = (long) fork();
	if (pid < 0) {
		app_log(lvl_err,
		        "%s: fork() failed\n",
		        __func__);
		(void) sem_destroy(s);
		goto ret_unmap;
	}

	/* Order calls so child() is always executed _before_ parent() */
	if (pid > 0) {
		int rv;
		do {
			errno = 0;
			rv = sem_wait(s);
		} while (rv == -1 && errno == EINTR);
		(void) sem_destroy(s);

		parent(pid);
	} else {
		child(0);

		(void) sem_post(s);
	}

	rc = 0;
ret_unmap:
	(void) munmap(s, sizeof(*s));
ret:
	return rc;
}
