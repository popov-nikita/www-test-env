all:
clean:
.PHONY: all clean

h_files := $(wildcard $(INC_DIR_ABS)/*)
files := process.c log.c
objects := $(patsubst %.c,%.o,$(files))

AR_FLAGS := rcs

all: $(LIB_FILENAME)

$(LIB_FILENAME): $(objects)
	ar $(AR_FLAGS) $@ $^

# Avoid distinct dependencies by declaring each object file depend on all custom header files
$(objects): %.o: %.c $(h_files)
	gcc $(CFLAGS) -c -o $@ $<

$(files) $(h_files) Makefile:

clean:
	rm -f $(objects) $(LIB_FILENAME)
