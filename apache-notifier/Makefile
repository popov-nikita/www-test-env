all:
clean:
.PHONY: all clean

prog_name := apache-notifier

files   := apache-notifier.c log.c
objects := $(patsubst %.c,%.o,$(files))

CFLAGS  := -O2 -Wall -Wextra -D_GNU_SOURCE

LDFLAGS := -no-pie -Wl,--gc-sections

all: $(prog_name)

$(prog_name): $(objects)
	gcc $(LDFLAGS) -o $@ $^

$(objects): %.o: %.c
	gcc $(CFLAGS) -c -o $@ $<

$(files):

clean:
	rm -f $(objects) $(prog_name)
