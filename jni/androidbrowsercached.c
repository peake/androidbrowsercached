/*
 * Copyright (C) 2013  Cal Peake <cp@absolutedigital.net>
 *
 * This program is free software; you can redistribute it
 * and/or modify it under the terms of the GNU General Public License
 * version 2 as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. For more details
 * see the full license text at either:
 *
 * <http://www.absolutedigital.net/lic/gplv2.txt> or
 * <http://www.gnu.org/licenses/old-licenses/gpl-2.0.html>
 *
 * androidbrowsercached.c - Android Browser Cache Daemon (ABCD)
 * created 14 Apr 2013
 * revision 2013050300
 * qcompile: gcc -W -Wall -o androidbrowsercached androidbrowsercached.c
 */

#include <sys/inotify.h>
#include <sys/mount.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>

#define BROWSER_DATA_DIR "/data/data/com.android.browser"
#define BROWSER_CACHE_DIR BROWSER_DATA_DIR "/cache"
#define BROWSER_CACHE_DIR_PERM 0700
#define BROWSER_CACHE_MOUNT_TAG "browser_cache"
#define BROWSER_CACHE_SIZE 50 /* megs, by default */
#define BROWSER_SESSION_FILE "browser_state.parcel"
#define BROWSER_SESSION_PATH BROWSER_CACHE_DIR "/" BROWSER_SESSION_FILE
#define BROWSER_SESSION_SAVE_PATH BROWSER_DATA_DIR "/." BROWSER_SESSION_FILE
#define BROWSER_SESSION_FILE_PERM 0600
#define ABCD_LOCK_FILE BROWSER_CACHE_DIR "/.androidbrowsercached.lock"
#define MOUNT_OPTS_LEN 10
#define BUF_SIZE 512

static void add_watch(const int fd)
{
	int s = 1;

	while (1) {
		if (inotify_add_watch(fd, BROWSER_SESSION_PATH, IN_MODIFY) == -1) {
			if (errno == ENOENT) {
				sleep(s);
				if (s < 4096) s*=2;
				continue;
			} else
				exit(1);
		} else
			return;
	}
}

int main()
{
	int ind, fi, fo, r;
	unsigned int mask;
	long size = BROWSER_CACHE_SIZE;
	char buf[BUF_SIZE], mount_opts[MOUNT_OPTS_LEN], *p;
	ssize_t bytes;
	uid_t uid;
	gid_t gid;
	struct stat sbuf;
	struct inotify_event *ine;

	if (stat(BROWSER_DATA_DIR, &sbuf) == -1)
		exit(1);

	uid = sbuf.st_uid;
	gid = sbuf.st_gid;

	if (stat(ABCD_LOCK_FILE, &sbuf) == 0 || errno != ENOENT)
		exit(1);

	if ((p = getenv("BROWSER_CACHE_SIZE")) != NULL) {
		size = strtol(p, (char **)NULL, 10);
		if (size < 1 || size > 999)
			size = BROWSER_CACHE_SIZE;
	}

	snprintf(mount_opts, MOUNT_OPTS_LEN, "size=%ldm", size);

	if (mount(BROWSER_CACHE_MOUNT_TAG, BROWSER_CACHE_DIR, "tmpfs",
		  MS_NODEV | MS_NOEXEC | MS_NOSUID, mount_opts) == -1)
		exit(1);

	chown(BROWSER_CACHE_DIR, uid, gid);
	chmod(BROWSER_CACHE_DIR, BROWSER_CACHE_DIR_PERM);

	if ((r = open(ABCD_LOCK_FILE, O_CREAT | O_EXCL | O_RDONLY, 0400)) == -1)
		exit(1);

	close(r);

	if (fork())
		exit(0);

	if ((fo = creat(BROWSER_SESSION_PATH, BROWSER_SESSION_FILE_PERM)) == -1)
		exit(1);

	chown(BROWSER_SESSION_PATH, uid, gid);
	chmod(BROWSER_SESSION_PATH, BROWSER_SESSION_FILE_PERM);

	/* initialize the browser session from the saved one if it exists */
	if (stat(BROWSER_SESSION_SAVE_PATH, &sbuf) == 0
	    && S_ISREG(sbuf.st_mode)) {
		if ((fi = open(BROWSER_SESSION_SAVE_PATH, O_RDONLY)) == -1)
			exit(1);
		while ((bytes = read(fi, &buf, BUF_SIZE)) > 0)
			write(fo, &buf, bytes);
		close(fi);
	}

	close(fo);

	if ((ind = inotify_init()) == -1)
		exit(1);

	add_watch(ind);

	while (1) {
		r = read(ind, &buf, BUF_SIZE);
		if (r < ((ssize_t)sizeof(*ine))) {
			if (r == -1) {
				switch (errno) {
				case EINTR:  /* interrupted by signal */
				case EINVAL: /* buffer too small? (unlikely) */
					continue;
				default:
					exit(1);
				}
			} else
				continue;
		}

		ine = (struct inotify_event *)buf;
		/* Save ine->mask here. For some yet unknown reason,
		 * it can get lost later on down the line. */
		mask = ine->mask;
		if (mask & IN_UNMOUNT)
			break; /* our tmpfs was unmounted, so we are done */

		if ((fi = open(BROWSER_SESSION_PATH, O_CREAT | O_RDONLY,
			       BROWSER_SESSION_FILE_PERM)) == -1)
			continue; /* hopefully just a temporary failure */

		chown(BROWSER_SESSION_PATH, uid, gid);
		chmod(BROWSER_SESSION_PATH, BROWSER_SESSION_FILE_PERM);

		if (mask & IN_IGNORED)
			add_watch(ind); /* session file was re-created */

		if ((fo = creat(BROWSER_SESSION_SAVE_PATH,
				BROWSER_SESSION_FILE_PERM)) == -1) {
			close(fi);
			continue; /* again, hopefully just temporary */
		}

		chown(BROWSER_SESSION_SAVE_PATH, uid, gid);
		chmod(BROWSER_SESSION_SAVE_PATH, BROWSER_SESSION_FILE_PERM);

		while ((bytes = read(fi, &buf, BUF_SIZE)) > 0)
			write(fo, &buf, bytes);

		close(fi);
		close(fo);
	}

	return 0;
}
