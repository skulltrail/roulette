.PHONY: all test lint format check setup help

SHELL := /bin/bash
BIN_DIR := bin
SHELLCHECK := $(BIN_DIR)/shellcheck
SHFMT := $(BIN_DIR)/shfmt

# Shell files to check (filter out non-existent files)
SHELL_FILES := $(wildcard scripts/*.sh) $(wildcard tests/*.sh) $(wildcard src/*.sh)
ifneq ($(wildcard roulette),)
	SHELL_FILES += roulette
endif

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

all: check test ## Run all checks and tests

setup: ## Install development tools and git hooks
	@bash scripts/setup-hooks.sh

test: ## Run BATS test suite
	@echo "Running tests..."
	@echo "Running BATS tests..."
	@if command -v bats >/dev/null 2>&1; then \
		bats tests/test_roulette.bats; \
	else \
		echo "Error: BATS not found. Install with: brew install bats-core"; \
		exit 1; \
	fi

test-all: test test-bats ## Run all tests (legacy and BATS)

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

check: lint format-check ## Run all pre-commit checks (same as commit hook)
	@echo ""
	@printf '\033[32mAll checks passed!\033[0m\n'

$(SHELLCHECK):
	@echo "shellcheck not found. Run 'make setup' first."
	@exit 1

$(SHFMT):
	@echo "shfmt not found. Run 'make setup' first."
	@exit 1
