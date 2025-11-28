#!/usr/bin/env bash
#
# Setup script for development hooks and tools
# Installs pre-commit hooks, shellcheck, and shfmt locally to the repo
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
BIN_DIR="${REPO_ROOT}/bin"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

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
      error "Unsupported OS: ${os_name}"
      exit 1
      ;;
  esac

  case "${arch_name}" in
    x86_64) arch="amd64" ;;
    arm64 | aarch64) arch="arm64" ;;
    *)
      error "Unsupported architecture: ${arch_name}"
      exit 1
      ;;
  esac

  echo "${os}_${arch}"
}

# Create tools directory
setup_dirs() {
  info "Setting up tools directory..."
  mkdir -p "${BIN_DIR}"
}

# Install shellcheck locally
install_shellcheck() {
  local version="v0.11.0"
  local platform
  platform=$(detect_platform)

  if [[ -x "${BIN_DIR}/shellcheck" ]]; then
    info "shellcheck already installed"
    return 0
  fi

  info "Installing shellcheck ${version}..."

  local os arch url
  os=$(echo "${platform}" | cut -d_ -f1)
  arch=$(echo "${platform}" | cut -d_ -f2)

  if [[ "${os}" == "darwin" ]]; then
    url="https://github.com/koalaman/shellcheck/releases/download/${version}/shellcheck-${version}.darwin.x86_64.tar.xz"
    # For macOS ARM, use the aarch64 binary
    if [[ "${arch}" == "arm64" ]]; then
      url="https://github.com/koalaman/shellcheck/releases/download/${version}/shellcheck-${version}.darwin.aarch64.tar.xz"
    fi
  else
    url="https://github.com/koalaman/shellcheck/releases/download/${version}/shellcheck-${version}.linux.x86_64.tar.xz"
    if [[ "${arch}" == "arm64" ]]; then
      url="https://github.com/koalaman/shellcheck/releases/download/${version}/shellcheck-${version}.linux.aarch64.tar.xz"
    fi
  fi

  local tmp_dir
  tmp_dir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '${tmp_dir}'" EXIT

  curl -sSL "${url}" | tar -xJ -C "${tmp_dir}"
  mv "${tmp_dir}"/shellcheck-*/shellcheck "${BIN_DIR}/"
  chmod +x "${BIN_DIR}/shellcheck"

  trap - EXIT
  rm -rf "${tmp_dir}"

  info "shellcheck installed successfully"
}

# Install shfmt locally
install_shfmt() {
  local version="v3.8.0"
  local platform
  platform=$(detect_platform)

  if [[ -x "${BIN_DIR}/shfmt" ]]; then
    info "shfmt already installed"
    return 0
  fi

  info "Installing shfmt ${version}..."

  local url="https://github.com/mvdan/sh/releases/download/${version}/shfmt_${version}_${platform}"

  curl -sSL "${url}" -o "${BIN_DIR}/shfmt"
  chmod +x "${BIN_DIR}/shfmt"

  info "shfmt installed successfully"
}

# Install commitlint (using a simple bash implementation to avoid Node.js dependency)
install_commit_hooks() {
  info "Setting up git hooks..."

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

  info "Git hooks installed successfully"
}

# Update .gitignore
update_gitignore() {
  local gitignore="${REPO_ROOT}/.gitignore"

  if ! grep -q "^bin/shellcheck$" "${gitignore}" 2>/dev/null; then
    info "Updating .gitignore..."
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
  info "Setting up development environment..."
  echo ""

  setup_dirs
  install_shellcheck
  install_shfmt
  install_commit_hooks
  update_gitignore

  echo ""
  info "Setup complete!"
  echo ""
  echo "Installed tools:"
  echo "  - shellcheck: ${BIN_DIR}/shellcheck"
  echo "  - shfmt: ${BIN_DIR}/shfmt"
  echo ""
  echo "Git hooks installed:"
  echo "  - pre-commit: Runs shellcheck and shfmt on staged shell scripts"
  echo "  - commit-msg: Validates conventional commit format"
  echo ""
  echo "To format a shell script:"
  echo "  ${BIN_DIR}/shfmt -w -i 2 -ci -bn <file>"
  echo ""
  echo "To lint a shell script:"
  echo "  ${BIN_DIR}/shellcheck <file>"
}

main "$@"
