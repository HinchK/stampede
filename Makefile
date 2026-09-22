# stampede — aggregate entry points
#
# The Suite Gate (lib/profile.sh TEST_CMD) resolves to `make test` for this
# repo (detect_ecosystem "make" branch). One command, all suites, failures
# propagate. Suites run under /bin/bash — macOS system bash 3.2 is the
# platform floor (#BASH32-FLOOR), not the dev shell's bash 5.

SHELL   := /bin/bash
TESTS   := $(sort $(wildcard tests/test_*.sh))
LINT_SH := bin/stampede herdr-loop-swarm.sh loop-bot-herd.sh $(wildcard lib/*.sh) $(wildcard lib/cli/*.sh)

.PHONY: test lint check version-check

# Version discipline (PUB-5): the changelog's top entry must name the
# version in VERSION. Publishing starts with the paperwork.
version-check:
	@v=$$(cat VERSION); \
	top=$$(sed -nE 's/^## \[([0-9]+\.[0-9]+\.[0-9]+)\].*/\1/p' CHANGELOG.md | head -n1); \
	if [ -z "$$top" ]; then printf 'version-check: no versioned entry in CHANGELOG.md\n' >&2; exit 1; fi; \
	if [ "$$v" != "$$top" ]; then \
	  printf 'version-check: VERSION=%s but CHANGELOG top entry is [%s]\n' "$$v" "$$top" >&2; exit 1; \
	fi; \
	printf 'version-check: %s == [%s] ✓\n' "$$v" "$$top"

# Run every suite; any failure fails the target (set -e stops the loop).
test:
	@set -e; \
	for t in $(TESTS); do \
	  printf '\n==> %s\n' "$$t"; \
	  $(SHELL) "$$t" || { printf '\n✖ FAILED: %s\n' "$$t" >&2; exit 1; }; \
	  printf '    OK\n'; \
	done; \
	printf '\nAll suites green (%d)\n' "$(words $(TESTS))"

# Lint gate: 0 shellcheck warnings is the bar (SC output goes to stderr).
# The interpreter resolves FIRST: py_compile must go through the shared
# tomllib-capable resolver (DOG-1), and the degraded-PATH failure has to be
# its actionable message — not a bare `shellcheck: command not found`, which
# would otherwise shadow it (shellcheck lives outside /usr/bin on macOS).
lint:
	@set -e; \
	PYTHON_BIN=$$($(SHELL) lib/pyenv.sh); \
	shellcheck $(LINT_SH); \
	for f in $(LINT_SH); do bash -n "$$f"; done; \
	"$$PYTHON_BIN" -m py_compile lib/telemetry.py; \
	printf 'Lint clean (%d shell files)\n' "$(words $(LINT_SH))"

# Everything CI (or a worker's Suite Gate) should run before a verdict.
check: lint test