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

INC_DIR := include
LIB_DIR := lib
EXE_FILENAME := $(notdir $(_CWD))
LIB_FILENAME := $(EXE_FILENAME).a
TAR_FILENAME := $(EXE_FILENAME).tar.gz

INC_DIR_ABS := $(realpath $(INC_DIR))
LIB_DIR_ABS := $(realpath $(LIB_DIR))
ifeq ($(and $(INC_DIR_ABS),$(LIB_DIR_ABS)),)
        $(error realpath failed)
endif
export LIB_FILENAME INC_DIR_ABS LIB_DIR_ABS

h_files := $(wildcard $(INC_DIR_ABS)/*)
files := apache-notifier.c
objects := $(patsubst %.c,%.o,$(files))

CFLAGS := -O2 -Wall -Wextra -Wno-unused-result -I$(INC_DIR_ABS) -D_GNU_SOURCE
export CFLAGS
LDFLAGS := -no-pie -pthread -Wl,--gc-sections

all: $(EXE_FILENAME)

# Order of linking is important:
#    As a general rule the libraries should follow application object files
#    in command line
# One can overcome this by using linking groups but this is another story...
$(EXE_FILENAME): $(objects) $(LIB_DIR)/$(LIB_FILENAME)
	gcc $(LDFLAGS) -o $@ $^

$(LIB_DIR)/$(LIB_FILENAME):
	$(MAKE) -C $(LIB_DIR) --no-print-directory $(LIB_FILENAME)

$(objects): %.o: %.c $(h_files)
	gcc $(CFLAGS) -c -o $@ $<

$(files) $(h_files) Makefile:

# Make sure everything is cleaned before creating archive!
make_targz:
	tar -c -z --transform 's@^@$(EXE_FILENAME)/@' -f $(TAR_FILENAME) $(files) Makefile $(INC_DIR) $(LIB_DIR)

clean:
	rm -f $(objects) $(EXE_FILENAME)
	$(MAKE) -C $(LIB_DIR) --no-print-directory clean
	if test -f $(TAR_FILENAME); then unlink $(TAR_FILENAME); fi

endif
