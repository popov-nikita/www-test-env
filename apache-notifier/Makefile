all:
make_targz:
clean:
.PHONY: all make_targz clean

_PROJ_ROOT_RAW := $(dir $(firstword $(MAKEFILE_LIST)))
_PROJ_ROOT := $(realpath $(_PROJ_ROOT_RAW))
_CWD := $(realpath $(CURDIR))

ifeq ($(and $(_PROJ_ROOT),$(_CWD)),)
        $(error realpath failed)
endif

_TARGETS := $(if $(MAKECMDGOALS),$(MAKECMDGOALS),all)

# Make sure we are run in CWD == PROJECT ROOT
ifneq ($(_CWD),$(_PROJ_ROOT))
$(_TARGETS):
	@$(MAKE) -C $(_PROJ_ROOT) --no-print-directory $(@)
else

ifeq ($(origin APACHE_NOTIFIER_TARGZ),undefined)
        $(warning Variable APACHE_NOTIFIER_TARGZ is not provided. Setting default value)
        APACHE_NOTIFIER_TARGZ := $(notdir $(_CWD)).tar.gz
endif

tar_gz_filename := $(APACHE_NOTIFIER_TARGZ)
executable_filename := $(patsubst %.tar.gz,%,$(tar_gz_filename))

h_files := $(wildcard include/*)
files := apache-notifier.c log.c process.c
objects := $(patsubst %.c,%.o,$(files))

CFLAGS := -O2 -Wall -Wextra -I./include -D_GNU_SOURCE
LDFLAGS := -no-pie -pthread -Wl,--gc-sections

all: $(executable_filename)

$(executable_filename): $(objects)
	gcc $(LDFLAGS) -o $@ $^

# Avoid distinct dependencies by declaring each object file depend on all custom header files
$(objects): %.o: %.c $(h_files)
	gcc $(CFLAGS) -c -o $@ $<

make_targz: $(tar_gz_filename)

$(tar_gz_filename): $(files) $(h_files) Makefile
	tar -c -z --transform 's@^@$(executable_filename)/@' -f $@ $^

$(files) $(h_files) Makefile:

clean:
	rm -f $(objects) $(executable_filename) $(tar_gz_filename)
endif
