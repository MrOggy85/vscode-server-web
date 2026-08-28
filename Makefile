# Everything `make lint` shellchecks. Globbed rather than listed, so a new script
# is picked up automatically. Two deliberate notes:
#   - install_additional_packages.sh is excluded because it is gitignored and
#     user-owned. CI only ever sees the .example it is copied from, so linting
#     the local copy would make `make lint` disagree with CI.
#   - the .example itself IS linted: it is COPY'd into the image and run during
#     the build, so a syntax error there breaks `run.sh` for everyone.
SHELL_SOURCES := vsc \
  $(filter-out install_additional_packages.sh,$(wildcard *.sh)) \
  $(wildcard *.sh.example)

# Scripts invoked as ./name, so the committed mode has to be 100755. An editor
# dropping it produces a "Permission denied" that looks nothing like a mode
# problem. entrypoint.sh and init-firewall.sh are absent on purpose — the
# Dockerfile chmods those, and make init chmods install_additional_packages.sh.
EXECUTABLES := run.sh vsc

.PHONY: init lint

init: install_additional_packages.sh allowed-domains.txt settings.json

# Shellcheck every script in SHELL_SOURCES. -x follows `source`d files. No
# exclusions: a finding is either fixed, or silenced at the site with an inline
# `# shellcheck disable=` and a reason.
# CI: .github/workflows/lint.yml
lint:
	@command -v shellcheck >/dev/null 2>&1 || { \
	  echo "shellcheck not found. Install with 'sudo apt install shellcheck' or 'brew install shellcheck'"; \
	  exit 1; \
	}
	@for f in $(EXECUTABLES); do \
	  test -x "$$f" || { echo "not executable: $$f  (chmod +x $$f)"; exit 1; }; \
	done
	shellcheck -x $(SHELL_SOURCES)

install_additional_packages.sh:
	cp install_additional_packages.sh.example install_additional_packages.sh
	chmod +x install_additional_packages.sh

allowed-domains.txt:
	cp allowed-domains.txt.example allowed-domains.txt

settings.json:
	cp settings.json.example settings.json
