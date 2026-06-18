.PHONY: all test lint format check setup build help coverage-check release-check ci-local

SHELL := /bin/bash
BIN_DIR := bin
SHELLCHECK := $(BIN_DIR)/shellcheck
SHFMT := $(BIN_DIR)/shfmt
BATS ?= bats
DEFAULT_BATS_FORMATTER := $(if $(filter dumb,$(TERM)),tap,$(if $(strip $(TERM)),pretty,tap))
BATS_FORMATTER ?= $(DEFAULT_BATS_FORMATTER)
BATS_FLAGS ?= --formatter $(BATS_FORMATTER)

# Shell files to check
SHELL_FILES := bin/roulette $(wildcard scripts/*.sh) $(wildcard tests/*.bats)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

all: build check test ## Build, lint, format-check, and test (ready for commit)

setup: ## Install development tools, git hooks, and Ruby dependencies
	@bash scripts/setup-hooks.sh

build: $(SHFMT) ## Format the roulette script
	@echo "Formatting roulette..."
	@$(SHFMT) -w -i 2 -ci -bn bin/roulette
	@echo "Build complete: ./bin/roulette"

test: ## Run BATS test suite
	@echo "Running tests..."
	@if command -v $(BATS) >/dev/null 2>&1; then \
		$(BATS) $(BATS_FLAGS) tests/test_roulette.bats; \
	else \
		echo "Error: BATS not found. Install with: brew install bats-core"; \
		exit 1; \
	fi

coverage-check: ## Run local equivalent of CI coverage job
	@echo "Running coverage workflow checks..."
	@if command -v $(BATS) >/dev/null 2>&1; then \
		report_file="$$(mktemp)"; \
		trap 'rm -f "$$report_file"' EXIT; \
		$(BATS) --formatter tap tests/test_roulette.bats > "$$report_file"; \
		test -s "$$report_file"; \
		$(BATS) --count tests/test_roulette.bats >/dev/null; \
	else \
		echo "Error: BATS not found. Install with: brew install bats-core"; \
		exit 1; \
	fi
	@echo "Coverage workflow checks passed!"

release-check: ## Validate local release metadata used by CI
	@echo "Validating release workflow inputs..."
	@bash scripts/validate-release-state.sh

ci-local: lint format-check release-check coverage-check ## Run all locally-runnable CI workflow checks
	@echo "Running local test workflow (headless mode)..."
	@TERM=dumb $(MAKE) test
	@echo ""
	@printf '\033[32mLocal CI workflow checks passed!\033[0m\n'

lint: $(SHELLCHECK) ## Run shellcheck on all shell files
	@echo "Running shellcheck..."
	@$(SHELLCHECK) -x $(SHELL_FILES)
	@echo "Linting passed!"

format: $(SHFMT) ## Format all shell files with shfmt
	@echo "Formatting shell files..."
	@$(SHFMT) -w -i 2 -ci -bn $(SHELL_FILES)
	@echo "Formatting complete!"

format-check: $(SHFMT) ## Check formatting without modifying files
	@echo "Checking formatting..."
	@$(SHFMT) -d -i 2 -ci -bn $(SHELL_FILES)
	@echo "Formatting check passed!"

check: lint format-check ## Run all pre-commit checks (lint + format-check)
	@echo ""
	@printf '\033[32mAll checks passed!\033[0m\n'

$(SHELLCHECK):
	@echo "shellcheck not found. Run 'make setup' first."
	@exit 1

$(SHFMT):
	@echo "shfmt not found. Run 'make setup' first."
	@exit 1
