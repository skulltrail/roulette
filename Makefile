.PHONY: all test lint format check setup build help

SHELL := /bin/bash
BIN_DIR := bin
SHELLCHECK := $(BIN_DIR)/shellcheck
SHFMT := $(BIN_DIR)/shfmt
SRC_DIR := src

# Shell files to check (includes generated roulette script)
SHELL_FILES := roulette $(wildcard scripts/*.sh) $(wildcard src/*.sh) $(wildcard tests/*.bats)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

all: build check test ## Build, lint, format-check, and test (ready for commit)

setup: ## Install development tools, git hooks, and Ruby dependencies
	@bash scripts/setup-hooks.sh

build: $(SHFMT) ## Build the roulette script using bashly
	@echo "Building roulette..."
	@if ! command -v bashly >/dev/null 2>&1; then \
		echo "Error: bashly not found. Run 'make setup' first."; \
		exit 1; \
	fi
	@bashly generate
	@$(SHFMT) -w -i 2 -ci -bn roulette
	@echo "Build complete: ./roulette"

test: ## Run BATS test suite
	@echo "Running tests..."
	@if command -v bats >/dev/null 2>&1; then \
		bats tests/test_roulette.bats; \
	else \
		echo "Error: BATS not found. Install with: brew install bats-core"; \
		exit 1; \
	fi

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
