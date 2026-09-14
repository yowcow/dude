# Entry point for the checks over this repository: `make lint test` plus
# `make manifest`. CI runs these same targets, so what a person runs by hand
# and what the gate runs cannot drift apart.
#
# The logic lives in the scripts, not in these recipes. A recipe carries no
# shebang, so ShellCheck would never check it; tests/lint.sh is a script
# precisely so that it appears in its own selection.

# Anchored at this Makefile's own directory rather than CURDIR, so `make -f
# /path/to/dude/Makefile` from elsewhere still finds the scripts.
HERE := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: all bump lint manifest test

all: lint test

# Rewrite the four version fields to one value, e.g. `make bump VERSION=1.2.3`.
# The value reaches bump.sh through the environment, never interpolated into
# the recipe: quoting $(VERSION) would not survive a value carrying a quote,
# which make expands before the shell sees the line.
bump: export VERSION := $(VERSION)
bump:
	"$(HERE)scripts/bump.sh" "$$VERSION"

# bash -n and ShellCheck over every shell file in the repository, selected by
# shebang.
lint:
	"$(HERE)tests/lint.sh"

# Official manifest validators plus JSON syntax checks for manifests outside
# their coverage.
manifest:
	"$(HERE)tests/manifest.sh"

# The offline test suite: every *_test.sh under tests/.
test:
	"$(HERE)tests/run.sh"
