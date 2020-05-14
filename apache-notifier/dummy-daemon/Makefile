all:
clean:
.PHONY: all clean

_CWD := $(realpath $(CURDIR))
ifeq ($(_CWD),)
        $(error realpath failed)
endif

EXE_FILENAME := $(notdir $(_CWD))

h_files := $(wildcard $(INC_DIR_ABS)/*)
files := dummy-daemon.c
objects := $(patsubst %.c,%.o,$(files))

all: $(EXE_FILENAME)

$(EXE_FILENAME): $(objects) $(LIB_DIR_ABS)/$(LIB_FILENAME)
	gcc $(LDFLAGS) -o $@ $^

$(LIB_DIR_ABS)/$(LIB_FILENAME):
	$(MAKE) -C $(LIB_DIR_ABS) --no-print-directory $(LIB_FILENAME)
.PHONY: $(LIB_DIR_ABS)/$(LIB_FILENAME)

$(objects): %.o: %.c $(h_files)
	gcc $(CFLAGS) -c -o $@ $<

$(files) $(h_files) Makefile:

clean:
	rm -f $(objects) $(EXE_FILENAME)
	$(MAKE) -C $(LIB_DIR_ABS) --no-print-directory clean
