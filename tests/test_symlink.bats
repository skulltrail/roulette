#!/usr/bin/env bats
# Tests for roulette symlink target

load helpers

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export HOME="${TEST_TEMP_DIR}/fakehome"
  mkdir -p "${HOME}"
}

teardown() {
  if [[ -n "${TEST_TEMP_DIR}" && -d "${TEST_TEMP_DIR}" ]]; then
    rm -rf "${TEST_TEMP_DIR}"
  fi
}

@test "make symlink creates symlink in ~/.local/bin" {
  run make symlink

  [[ "${status}" -eq 0 ]]
  [[ -L "${HOME}/.local/bin/roulette" ]]

  run "${HOME}/.local/bin/roulette" --version
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "make symlink supports custom PREFIX" {
  local target_prefix="${TEST_TEMP_DIR}/custom-prefix"
  run make symlink PREFIX="${target_prefix}"

  [[ "${status}" -eq 0 ]]
  [[ -L "${target_prefix}/bin/roulette" ]]

  run "${target_prefix}/bin/roulette" --version
  [[ "${status}" -eq 0 ]]
}

@test "make symlink supports custom BINDIR" {
  local target_bindir="${TEST_TEMP_DIR}/custom-bin"
  run make symlink BINDIR="${target_bindir}"

  [[ "${status}" -eq 0 ]]
  [[ -L "${target_bindir}/roulette" ]]

  run "${target_bindir}/roulette" --version
  [[ "${status}" -eq 0 ]]
}

@test "make symlink replaces existing symlink or file" {
  local target_bindir="${TEST_TEMP_DIR}/replace-bin"
  mkdir -p "${target_bindir}"
  touch "${target_bindir}/roulette"

  run make symlink BINDIR="${target_bindir}"

  [[ "${status}" -eq 0 ]]
  [[ -L "${target_bindir}/roulette" ]]

  run "${target_bindir}/roulette" --version
  [[ "${status}" -eq 0 ]]
}
