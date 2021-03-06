#
# PM-QA validation test suite for the power management on Linux
#
# Copyright (C) 2011, Linaro Limited.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# Contributors:
#     Daniel Lezcano <daniel.lezcano@linaro.org> (IBM Corporation)
#       - initial API and implementation

SNT=$(wildcard *sanity.sh)
TST=$(sort $(wildcard *[!{sanity}].sh))
LOG=$(TST:.sh=.log)

# Default flags passed to the compiler.
CFLAGS?=-g -Wall

# Required compiler flags to build the utils.
FLAGS?=-pthread

# Default compiler to build the utils.
CC?=gcc

# All utils' source files.
SRC=$(wildcard ../utils/*.c) $(wildcard ../cpuidle/*.c)

# All executable files built from the utils' source files.
EXEC=$(SRC:%.c=%)

.PHONY: build_utils check clean recheck run_tests uncheck

# Build the utils and run the tests.
build_utils: $(EXEC)

SANITY_STATUS:= $(shell if test $(SNT) && test -f $(SNT); then \
		sudo ./$(SNT); if test "$$?" -eq 0; then echo 0; else \
		echo 1; fi; else echo 1; fi)

ifeq "$(SANITY_STATUS)" "1"
run_tests: uncheck $(EXEC) $(LOG)

%.log: %.sh
	@echo "###"
	@echo "### $(<:.sh=):"
	@echo -n "### "; cat $(<:.sh=.txt);
	@echo -n "### "; grep "URL :" ./$< | awk '/http/{print $$NF}'
	@echo "###"
	-@sudo ./$< 2> $@
else
run_tests:
	./$(SNT)
#	@cat $(<:.sh=.txt)
endif

# Target for building all the utils we need, from sources.
$(EXEC): $(SRC)
	$(CC) $(CFLAGS) $(FLAGS) $@.c -o $@

clean:
	rm -f *.o $(EXEC)

check: build_utils run_tests

uncheck:
	-@$(shell test ! -z "$(LOG)" && rm -f $(LOG))

recheck: uncheck check
