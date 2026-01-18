#!/usr/bin/env bash
#
# Setup script for development hooks and tools
# Installs pre-commit hooks, shellcheck, and shfmt locally to the repo
#

set -euo pipefail

# Get script directory using realpath for robustness
if command -v realpath >/dev/null 2>&1; then
  SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
  SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")"
else
  # Fallback for systems without realpath
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
fi
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
BIN_DIR="${REPO_ROOT}/bin"

# Colors and symbols for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Symbols
SYM_OK="${GREEN}✓${NC}"
SYM_FAIL="${RED}✗${NC}"
SYM_WARN="${YELLOW}⚠${NC}"
SYM_ARROW="${CYAN}→${NC}"
SYM_DOT="${DIM}•${NC}"

step() { echo -e "  ${SYM_ARROW} $*"; }
step_done() { echo -e "  ${SYM_OK} $*"; DID_INSTALL=true; }
warn() { echo -e "  ${SYM_WARN} ${YELLOW}$*${NC}"; }
fail() { echo -e "  ${SYM_FAIL} ${RED}$*${NC}"; }

# Detect OS and architecture
detect_platform() {
  local os arch
  local os_name arch_name
  os_name=$(uname -s)
  arch_name=$(uname -m)

  case "${os_name}" in
  Darwin) os="darwin" ;;
  Linux) os="linux" ;;
  *)
    fail "Unsupported OS: ${os_name}"
    exit 1
    ;;
  esac

  case "${arch_name}" in
  x86_64) arch="amd64" ;;
  arm64 | aarch64) arch="arm64" ;;
  *)
    fail "Unsupported architecture: ${arch_name}"
    exit 1
    ;;
  esac

  echo "${os}_${arch}"
}

# Create tools directory
setup_dirs() {
  mkdir -p "${BIN_DIR}"
}

# Install shellcheck locally
install_shellcheck() {
  local version="v0.11.0"
  local platform
  platform=$(detect_platform)

  # Check if already installed with correct version
  if [[ -x "${BIN_DIR}/shellcheck" ]]; then
    local installed_version
    installed_version=$("${BIN_DIR}/shellcheck" --version 2>/dev/null | grep -oE 'version: [0-9.]+' | cut -d' ' -f2 || echo "")
    if [[ "v${installed_version}" == "${version}" ]]; then
      SHELLCHECK_STATUS="exists"
      return 0
    fi
    step "Upgrading shellcheck from v${installed_version} to ${version}..."
  else
    step "Installing shellcheck ${version}..."
  fi

  local os arch url
  os=$(echo "${platform}" | cut -d_ -f1)
  arch=$(echo "${platform}" | cut -d_ -f2)

  if [[ "${os}" == "darwin" ]]; then
    url="https://github.com/koalaman/shellcheck/releases/download/${version}/shellcheck-${version}.darwin.x86_64.tar.xz"
    [[ "${arch}" == "arm64" ]] && url="https://github.com/koalaman/shellcheck/releases/download/${version}/shellcheck-${version}.darwin.aarch64.tar.xz"
  else
    url="https://github.com/koalaman/shellcheck/releases/download/${version}/shellcheck-${version}.linux.x86_64.tar.xz"
    [[ "${arch}" == "arm64" ]] && url="https://github.com/koalaman/shellcheck/releases/download/${version}/shellcheck-${version}.linux.aarch64.tar.xz"
  fi

  local tmp_dir
  tmp_dir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '${tmp_dir}'" EXIT

  if curl -sSL "${url}" | tar -xJ -C "${tmp_dir}" &&
    mv "${tmp_dir}"/shellcheck-*/shellcheck "${BIN_DIR}/" &&
    chmod +x "${BIN_DIR}/shellcheck"; then
    step_done "Installed shellcheck ${version}"
    SHELLCHECK_STATUS="installed"
  else
    fail "Failed to install shellcheck"
    SHELLCHECK_STATUS="failed"
  fi

  trap - EXIT
  rm -rf "${tmp_dir}"
}

# Install shfmt locally
install_shfmt() {
  local version="v3.8.0"
  local platform
  platform=$(detect_platform)

  # Check if already installed with correct version
  if [[ -x "${BIN_DIR}/shfmt" ]]; then
    local installed_version
    installed_version=$("${BIN_DIR}/shfmt" --version 2>/dev/null || echo "")
    if [[ "${installed_version}" == "${version}" ]]; then
      SHFMT_STATUS="exists"
      return 0
    fi
    step "Upgrading shfmt from ${installed_version} to ${version}..."
  else
    step "Installing shfmt ${version}..."
  fi

  local url="https://github.com/mvdan/sh/releases/download/${version}/shfmt_${version}_${platform}"

  if curl -sSL "${url}" -o "${BIN_DIR}/shfmt" && chmod +x "${BIN_DIR}/shfmt"; then
    step_done "Installed shfmt ${version}"
    SHFMT_STATUS="installed"
  else
    fail "Failed to install shfmt"
    SHFMT_STATUS="failed"
  fi
}

# Install git hooks
install_commit_hooks() {
  local hooks_dir="${REPO_ROOT}/.git/hooks"
  mkdir -p "${hooks_dir}"

  # Create pre-commit hook
  cat >"${hooks_dir}/pre-commit" <<'HOOK'
#!/usr/bin/env bash
#
# Pre-commit hook: runs shellcheck and shfmt on staged shell scripts
#

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
TOOLS_BIN="${REPO_ROOT}/bin"

# Use local tools if available, otherwise fall back to system
SHELLCHECK="${TOOLS_BIN}/shellcheck"
SHFMT="${TOOLS_BIN}/shfmt"

[[ -x "${SHELLCHECK}" ]] || SHELLCHECK="shellcheck"
[[ -x "${SHFMT}" ]] || SHFMT="shfmt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

error_count=0

# Get staged shell scripts
staged_files=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(sh|bash)$' || true)
# Also check files without extension that have shell shebang
staged_scripts=$(git diff --cached --name-only --diff-filter=ACM | while read -r file; do
    if [[ -f "${file}" ]] && head -1 "${file}" 2>/dev/null | grep -qE '^#!.*\b(ba)?sh\b'; then
        echo "${file}"
    fi
done || true)

all_files=$(echo -e "${staged_files}\n${staged_scripts}" | sort -u | grep -v '^$' || true)

if [[ -z "${all_files}" ]]; then
    exit 0
fi

echo "Running shell linting and formatting checks..."

# Run shellcheck
if command -v "${SHELLCHECK}" &>/dev/null; then
    echo "Running shellcheck..."
    for file in ${all_files}; do
        if ! "${SHELLCHECK}" -x "${file}"; then
            ((error_count++))
        fi
    done
else
    echo -e "${RED}shellcheck not found. Run 'scripts/setup-hooks.sh' to install.${NC}"
    ((error_count++))
fi

# Run shfmt (check mode)
if command -v "${SHFMT}" &>/dev/null; then
    echo "Checking formatting with shfmt..."
    for file in ${all_files}; do
        if ! "${SHFMT}" -d -i 2 -ci -bn "${file}" >/dev/null 2>&1; then
            echo -e "${RED}Formatting issue in: ${file}${NC}"
            echo "Run: ${SHFMT} -w -i 2 -ci -bn ${file}"
            ((error_count++))
        fi
    done
else
    echo -e "${RED}shfmt not found. Run 'scripts/setup-hooks.sh' to install.${NC}"
    ((error_count++))
fi

if [[ ${error_count} -gt 0 ]]; then
    echo -e "${RED}Pre-commit checks failed with ${error_count} error(s)${NC}"
    exit 1
fi

echo -e "${GREEN}All pre-commit checks passed!${NC}"
HOOK
  chmod +x "${hooks_dir}/pre-commit"

  # Create commit-msg hook for conventional commits
  cat >"${hooks_dir}/commit-msg" <<'HOOK'
#!/usr/bin/env bash
#
# Commit message hook: validates conventional commit format
#
# Format: <type>[optional scope]: <description>
#
# Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
#

set -euo pipefail

commit_msg_file="$1"
commit_msg=$(cat "${commit_msg_file}")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Skip merge commits
if echo "${commit_msg}" | grep -qE '^Merge '; then
    exit 0
fi

# Conventional commit regex
# type(optional-scope): description
# type: description
conventional_regex='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-zA-Z0-9_-]+\))?: .{1,}'

if ! echo "${commit_msg}" | head -1 | grep -qE "${conventional_regex}"; then
    echo -e "${RED}ERROR: Commit message does not follow Conventional Commits format${NC}"
    echo ""
    echo "Expected format: <type>[optional scope]: <description>"
    echo ""
    echo "Valid types:"
    echo "  feat:     A new feature"
    echo "  fix:      A bug fix"
    echo "  docs:     Documentation only changes"
    echo "  style:    Changes that do not affect the meaning of the code"
    echo "  refactor: A code change that neither fixes a bug nor adds a feature"
    echo "  perf:     A code change that improves performance"
    echo "  test:     Adding missing tests or correcting existing tests"
    echo "  build:    Changes that affect the build system or dependencies"
    echo "  ci:       Changes to CI configuration files and scripts"
    echo "  chore:    Other changes that don't modify src or test files"
    echo "  revert:   Reverts a previous commit"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  feat: add user authentication"
    echo "  fix(api): resolve null pointer exception"
    echo "  docs: update README with installation steps"
    echo ""
    echo -e "Your message: ${RED}${commit_msg}${NC}"
    exit 1
fi

echo -e "${GREEN}Commit message follows Conventional Commits format ✓${NC}"
HOOK
  chmod +x "${hooks_dir}/commit-msg"
}

# Update .gitignore
update_gitignore() {
  local gitignore="${REPO_ROOT}/.gitignore"

  if ! grep -q "^bin/shellcheck$" "${gitignore}" 2>/dev/null; then
    {
      echo ""
      echo "# Local development tools"
      echo "bin/shellcheck"
      echo "bin/shfmt"
    } >>"${gitignore}"
  fi
}

# Main
main() {
  # Initialize status tracking
  SHELLCHECK_STATUS=""
  SHFMT_STATUS=""
  DID_INSTALL=false

  echo ""
  echo -e "${BOLD}Setting up development environment${NC}"
  echo ""

  setup_dirs
  install_shellcheck
  install_shfmt
  install_commit_hooks
  update_gitignore

  # Add blank line after installs only if we installed something
  $DID_INSTALL && echo ""

  echo -e "${CYAN}───────────────────────────────────${NC}"
  echo -e "${BOLD}  Summary${NC}"
  echo -e "${CYAN}───────────────────────────────────${NC}"

  # Tools
  if [[ -x "${BIN_DIR}/shellcheck" ]]; then
    printf "  ${SYM_OK} ${BOLD}%-12s${NC} ${DIM}%s${NC}\n" "shellcheck" "linter"
  else
    printf "  ${SYM_FAIL} ${BOLD}%-12s${NC} ${DIM}%s${NC}\n" "shellcheck" "linter"
  fi

  if [[ -x "${BIN_DIR}/shfmt" ]]; then
    printf "  ${SYM_OK} ${BOLD}%-12s${NC} ${DIM}%s${NC}\n" "shfmt" "formatter"
  else
    printf "  ${SYM_FAIL} ${BOLD}%-12s${NC} ${DIM}%s${NC}\n" "shfmt" "formatter"
  fi

  # Hooks
  if [[ -x "${REPO_ROOT}/.git/hooks/pre-commit" ]]; then
    printf "  ${SYM_OK} ${BOLD}%-12s${NC} ${DIM}%s${NC}\n" "pre-commit" "git hook"
  else
    printf "  ${SYM_FAIL} ${BOLD}%-12s${NC} ${DIM}%s${NC}\n" "pre-commit" "git hook"
  fi

  if [[ -x "${REPO_ROOT}/.git/hooks/commit-msg" ]]; then
    printf "  ${SYM_OK} ${BOLD}%-12s${NC} ${DIM}%s${NC}\n" "commit-msg" "git hook"
  else
    printf "  ${SYM_FAIL} ${BOLD}%-12s${NC} ${DIM}%s${NC}\n" "commit-msg" "git hook"
  fi

  echo -e "${CYAN}───────────────────────────────────${NC}"
  echo ""
}

main "$@"
