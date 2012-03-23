# Copyright (c) 2012 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

LIBDIR = lib
PRELOADPATH = \"/$(LIBDIR)/libminijailpreload.so\"
CFLAGS += -fPIC -Wall -Wextra -Werror -DPRELOADPATH="$(PRELOADPATH)"
CFLAGS += -fvisibility=internal

all : minijail0 libminijail.so libminijailpreload.so

tests : libminijail_unittest.wrapper syscall_filter_unittest

minijail0 : libsyscalls.gen.o libminijail.o minijail0.c
	$(CC) $(CFLAGS) -o $@ $^ -lcap

libminijail.so : libminijail.o libsyscalls.gen.o
	$(CC) $(CFLAGS) -shared -o $@ $^ -lcap

# Allow unittests to access what are normally internal symbols.
libminijail_unittest.wrapper :
	$(MAKE) $(MAKEARGS) test-clean
	$(MAKE) $(MAKEARGS) libminijail_unittest
	$(MAKE) $(MAKEARGS) test-clean

libminijail_unittest : CFLAGS := $(filter-out -fvisibility=%,$(CFLAGS))
libminijail_unittest : libminijail_unittest.o libminijail.o libsyscalls.gen.o
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(filter-out $(CFLAGS_FILE),$^) -lcap

libminijailpreload.so : libminijailpreload.c libsyscalls.gen.o libminijail.o
	$(CC) $(CFLAGS) -shared -o $@ $^ -ldl -lcap

libminijail.o : libminijail.c libminijail.h

libminijail_unittest.o : libminijail_unittest.c test_harness.h
	$(CC) $(CFLAGS) -c -o $@ $<

libsyscalls.gen.o : libsyscalls.gen.c libsyscalls.h

syscall_filter_unittest : syscall_filter_unittest.o syscall_filter.o bpf.o \
		libsyscalls.gen.o test_harness.h
	$(CC) $(CFLAGS) -o $@ $^

syscall_filter_unittest.o : syscall_filter_unittest.c test_harness.h
	$(CC) $(CFLAGS) -c -o $@ $<

syscall_filter.o : syscall_filter.c

bpf.o : bpf.c

# sed expression which extracts system calls that are
# defined via asm/unistd.h.  It converts them from:
#  #define __NR_read
# to:
# #ifdef __NR_read
#  { "read", __NR_read },
# #endif
# All other lines will not be emitted.  The sed expression lives in its
# own macro to allow clean line wrapping.
define sed-multiline
	's/#define \(__NR_\)\([a-z0-9_]*\)$$/#ifdef \1\2\n\
	 { "\2", \1\2 },\n#endif/g p;'
endef

# Generates a header file with a system call table made up of "name",
# syscall_nr entries by including the build target <asm/unistd.h> and
# emitting the list of defines.  Use of the compiler is needed to
# dereference the actual provider of syscall definitions.
#   E.g., asm/unistd_32.h or asm/unistd_64.h, etc.
define gen_syscalls
	(set -e; \
	 echo '/* GENERATED BY MAKEFILE */'; \
	 echo '#include <stddef.h>'; \
	 echo '#include <asm/unistd.h>'; \
	 echo '#include "libsyscalls.h"'; \
	 echo "const struct syscall_entry syscall_table[] = {"; \
	 echo "#include <asm/unistd.h>" | \
	   $(CC) $(CFLAGS) -dN - -E | sed -ne $(sed-multiline); \
	 echo "  { NULL, -1 },"; \
	 echo "};" ) > $1
endef

# Only regenerate libsyscalls.gen.c if the Makefile or header changes.
# NOTE! This will not detect if the file is not appropriate for the target.
libsyscalls.gen.c : Makefile libsyscalls.h
	@printf "Generating target-arch specific $@ . . . "
	@$(call gen_syscalls,$@)
	@printf "done.\n"

# Only clean up files affected by the CFLAGS change for testing.
test-clean :
	@rm -f libminijail.o libminijail_unittest.o libsyscalls.gen.o

clean : test-clean
	@rm -f libminijail.o libminijailpreload.so minijail0
	@rm -f libminijail.so
	@rm -f libminijail_unittest
	@rm -f libsyscalls.gen.c
	@rm -f syscall_filter.o bpf.o
	@rm -f syscall_filter_unittest syscall_filter_unittest.o
