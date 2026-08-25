# Entry point for the checks over this repository: `make lint test`. CI runs
# these same targets, so what a person runs by hand and what the gate runs
# cannot drift apart.
#
# The logic lives in the scripts, not in these recipes. A recipe carries no
# shebang, so ShellCheck would never check it; tests/lint.sh is a script
# precisely so that it appears in its own selection.

# Anchored at this Makefile's own directory rather than CURDIR, so `make -f
# /path/to/dude/Makefile` from elsewhere still finds the scripts.
HERE := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: all lint test

all: lint test

# bash -n and ShellCheck over every shell file in the repository, selected by
# shebang.
lint:
	"$(HERE)tests/lint.sh"

# The offline test suite: every *_test.sh under tests/.
test:
	"$(HERE)tests/run.sh"
