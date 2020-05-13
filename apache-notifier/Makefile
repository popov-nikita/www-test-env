all:
make_targz:
clean:
.PHONY: all make_targz clean

tar_gz_target  := $(APACHE_NOTIFIER_TARGZ)
program_target := $(patsubst %.tar.gz,%,$(APACHE_NOTIFIER_TARGZ))

h_files := log.h process.h
files   := apache-notifier.c log.c process.c
objects := $(patsubst %.c,%.o,$(files))

CFLAGS  := -O2 -Wall -Wextra -D_GNU_SOURCE

LDFLAGS := -no-pie -pthread -Wl,--gc-sections

all: $(program_target)

$(program_target): $(objects)
	gcc $(LDFLAGS) -o $@ $^

$(objects): %.o: %.c
	gcc $(CFLAGS) -c -o $@ $<

make_targz: $(tar_gz_target)

$(tar_gz_target): $(files) $(h_files) Makefile
	tar -c -z --transform 's@^@$(program_target)/@' -f $@ $^

$(files) $(h_files) Makefile:

clean:
	rm -f $(objects) $(program_target) $(tar_gz_target)
