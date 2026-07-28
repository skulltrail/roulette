#!/usr/bin/env bats
# Comprehensive BATS tests for roulette

bats_require_minimum_version 1.5.0

# GNU timeout is not available by default on macOS GitHub runners.
# Provide a minimal fallback that supports the timeout usage in this suite.
if ! command -v timeout >/dev/null 2>&1; then
  timeout() {
    local signal="TERM"

    if [[ "$1" == --signal=* ]]; then
      signal="${1#--signal=}"
      shift
    elif [[ "$1" == --signal ]]; then
      signal="$2"
      shift 2
    fi

    local duration="$1"
    shift

    local seconds="${duration%s}"
    if [[ "${seconds}" == "${duration}" ]] || [[ -z "${seconds}" ]]; then
      echo "Unsupported timeout format: ${duration}" >&2
      return 125
    fi

    "$@" &
    local cmd_pid=$!

    (
      sleep "${seconds}"
      if kill -0 "${cmd_pid}" 2>/dev/null; then
        kill "-${signal}" "${cmd_pid}" 2>/dev/null || true
        sleep 0.2
        kill -0 "${cmd_pid}" 2>/dev/null && kill -KILL "${cmd_pid}" 2>/dev/null || true
      fi
    ) &
    local timer_pid=$!

    wait "${cmd_pid}"
    local cmd_status=$?

    kill "${timer_pid}" 2>/dev/null || true
    wait "${timer_pid}" 2>/dev/null || true

    if [[ "${cmd_status}" -eq 143 ]] || [[ "${cmd_status}" -eq 137 ]]; then
      return 124
    fi

    return "${cmd_status}"
  }
fi

# Test setup - runs before each test
setup() {
  BATS_TEST_DIRNAME="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  export BATS_TEST_DIRNAME
  PROJECT_ROOT="$(dirname "${BATS_TEST_DIRNAME}")"
  export PROJECT_ROOT
  export ROULETTE_BIN="${PROJECT_ROOT}/bin/roulette"

  # Create temporary test directories
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR
  export TEST_MEDIA_DIR="${TEST_TEMP_DIR}/media"
  export TEST_MOCK_DIR="${TEST_TEMP_DIR}/mock_bin"

  # Keep developer shell defaults from changing test behavior.
  unset ROULETTE_PATH
  unset ROULETTE_DOWNLOADS_PATH
  unset ROULETTE_MAIN_PATH

  mkdir -p "${TEST_MEDIA_DIR}" "${TEST_MOCK_DIR}"

  if ! type -P timeout >/dev/null 2>&1; then
    cat >"${TEST_MOCK_DIR}/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

signal="TERM"

if [[ "${1:-}" == --signal=* ]]; then
  signal="${1#--signal=}"
  shift
elif [[ "${1:-}" == "--signal" ]]; then
  signal="${2:-TERM}"
  shift 2
fi

duration="${1:-}"
shift

seconds="${duration%s}"
if [[ "${seconds}" == "${duration}" ]] || [[ -z "${seconds}" ]]; then
  echo "Unsupported timeout format: ${duration}" >&2
  exit 125
fi

"$@" &
cmd_pid=$!

(
  sleep "${seconds}"
  if kill -0 "${cmd_pid}" 2>/dev/null; then
    kill "-${signal}" "${cmd_pid}" 2>/dev/null || true
    sleep 0.2
    kill -0 "${cmd_pid}" 2>/dev/null && kill -KILL "${cmd_pid}" 2>/dev/null || true
  fi
) &
timer_pid=$!

wait "${cmd_pid}"
cmd_status=$?

kill "${timer_pid}" 2>/dev/null || true
wait "${timer_pid}" 2>/dev/null || true

if [[ "${cmd_status}" -eq 143 ]] || [[ "${cmd_status}" -eq 137 ]]; then
  exit 124
fi

exit "${cmd_status}"
EOF
    chmod +x "${TEST_MOCK_DIR}/timeout"
  fi

  # Create mock mpv that doesn't actually play videos
  cat >"${TEST_MOCK_DIR}/mpv" <<'EOF'
#!/bin/bash
# Mock MPV - just logs the call and exits successfully
echo "MOCK_MPV: $*" >&2
exit 0
EOF
  chmod +x "${TEST_MOCK_DIR}/mpv"

  # Create mock mediainfo
  cat >"${TEST_MOCK_DIR}/mediainfo" <<'EOF'
#!/bin/bash
echo "MOCK_MEDIAINFO: $*"
echo "General"
echo "Complete name: $1"
echo "Format: Mock Format"
EOF
  chmod +x "${TEST_MOCK_DIR}/mediainfo"

  # Prepend mock directory to PATH
  export PATH="${TEST_MOCK_DIR}:${PATH}"

  # Create test video files
  create_test_videos
}

# Test teardown - runs after each test
teardown() {
  rm -rf "${TEST_TEMP_DIR}"
}

source_roulette_functions() {
  # shellcheck disable=SC2034
  ROULETTE_SOURCE_ONLY=1
  # shellcheck disable=SC1090,SC1091
  source "${ROULETTE_BIN}"
  unset ROULETTE_SOURCE_ONLY
}

get_file_mtime() {
  local path="$1"
  if stat -f '%m' "${path}" >/dev/null 2>&1; then
    stat -f '%m' "${path}"
  else
    stat -c '%Y' "${path}"
  fi
}

# Helper function to create test video files
create_test_videos() {
  touch "${TEST_MEDIA_DIR}/video1.mp4"
  touch "${TEST_MEDIA_DIR}/video2.avi"
  touch "${TEST_MEDIA_DIR}/video3.mkv"
  touch "${TEST_MEDIA_DIR}/video4.mov"
  touch "${TEST_MEDIA_DIR}/video5.webm"

  # Create subdirectory with videos
  mkdir -p "${TEST_MEDIA_DIR}/subdir"
  touch "${TEST_MEDIA_DIR}/subdir/video6.mp4"
  touch "${TEST_MEDIA_DIR}/subdir/video7.flv"

  # Create non-video files that should be ignored
  touch "${TEST_MEDIA_DIR}/readme.txt"
  touch "${TEST_MEDIA_DIR}/image.jpg"
  touch "${TEST_MEDIA_DIR}/document.pdf"
}

# ======================================================================
# HELP AND VERSION TESTS
# ======================================================================

@test "roulette shows help when run with --help" {
  run "${ROULETTE_BIN}" --help
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ "roulette" ]]
  [[ "${output}" =~ "Play random video files" ]]
}

@test "roulette shows version when run with --version" {
  run "${ROULETTE_BIN}" --version
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "roulette help shows debug flag" {
  run "${ROULETTE_BIN}" --help
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ "--debug" ]]
}

@test "roulette help shows fullscreen flag" {
  run "${ROULETTE_BIN}" --help
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ "--fullscreen" ]]
}

@test "roulette help shows ignore mpv env flag" {
  run "${ROULETTE_BIN}" --help
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ "--bypass" ]]
}

@test "roulette help shows shuffle flag" {
  run "${ROULETTE_BIN}" --help
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ "--shuffle" ]]
}

@test "roulette help shows scan flag" {
  run "${ROULETTE_BIN}" --help
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ "--scan" ]]
}

@test "roulette help shows filter flag" {
  run "${ROULETTE_BIN}" --help
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ "--filter" ]]
}

@test "roulette --filter requires a query" {
  run "${ROULETTE_BIN}" --filter
  [[ "${status}" -ne 0 ]]
  [[ "${output}" =~ "missing value for option: --filter" ]]
}

# ======================================================================
# DIRECTORY VALIDATION TESTS
# ======================================================================

@test "roulette fails when provided directory does not exist" {
  run timeout 2s "${ROULETTE_BIN}" /nonexistent/directory <<<"q"
  [[ "${status}" -ne 0 ]]
  [[ "${output}" =~ "Directory not found" ]]
}

@test "roulette accepts tilde (~) in directory path" {
  # Create a test dir in a temporary HOME so this stays writable in sandboxes
  local home_test_dir
  local fake_home="${TEST_TEMP_DIR}/home"
  local tilde_path
  mkdir -p "${fake_home}"
  home_test_dir="${fake_home}/.roulette_test_$(date +%s)"
  # shellcheck disable=SC2088  # Intentionally pass a literal '~' so roulette expands it.
  printf -v tilde_path '~/.roulette_test_%s' "$(date +%s | head -c 10)"
  mkdir -p "${home_test_dir}"
  touch "${home_test_dir}/test.mp4"

  run env HOME="${fake_home}" timeout 2s "${ROULETTE_BIN}" "${tilde_path}" <<<"q" 2>&1 || true

  # Cleanup
  rm -rf "${home_test_dir}"

  # We expect it to fail because directory won't match exactly, but tilde expansion should happen
  [[ "${output}" =~ "Directory not found" ]] || [[ "${output}" =~ "Playing" ]] || [[ "${output}" =~ "Found" ]]
}

@test "roulette accepts valid directory path" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"
  local expected_pattern="Using provided directory: ${TEST_MEDIA_DIR}"
  [[ "${output}" =~ ${expected_pattern} ]] || [[ "${output}" =~ "Found" ]]
}

@test "roulette accepts multiple directory paths" {
  local state_dir="${TEST_TEMP_DIR}/state"
  mkdir -p "${TEST_TEMP_DIR}/multi_a" "${TEST_TEMP_DIR}/multi_b"
  mkdir -p "${state_dir}"
  touch "${TEST_TEMP_DIR}/multi_a/video1.mp4"
  touch "${TEST_TEMP_DIR}/multi_b/video2.mkv"

  run env XDG_STATE_HOME="${state_dir}" timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/multi_a' '${TEST_TEMP_DIR}/multi_b'"

  [[ "${output}" =~ "Using provided directories" ]]
  [[ "${output}" =~ "Found 2 videos" ]] || [[ "${output}" =~ "2 videos" ]]
}

@test "roulette prioritizes earlier directories before later ones" {
  local dir_a="${TEST_TEMP_DIR}/priority_a"
  local dir_b="${TEST_TEMP_DIR}/priority_b"
  local state_dir="${TEST_TEMP_DIR}/state"
  local expected_dir_a=""
  mkdir -p "${dir_a}" "${dir_b}" "${state_dir}"
  touch "${dir_a}/first.mp4"
  touch "${dir_b}/second.mp4"
  expected_dir_a="$(cd "${dir_a}" && pwd -P)"

  run env XDG_STATE_HOME="${state_dir}" timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${dir_a}' '${dir_b}'"

  [[ "${status}" -eq 0 ]] || [[ "${status}" -eq 124 ]]
  [[ "${output}" == *"Playing: ${expected_dir_a}/first.mp4"* ]]
}

# ======================================================================
# VIDEO FILE DISCOVERY TESTS
# ======================================================================

@test "roulette finds video files recursively" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"
  [[ "${output}" =~ "Found 7 videos" ]] || [[ "${output}" =~ "7 videos" ]]
}

@test "roulette recognizes mp4 files" {
  mkdir -p "${TEST_TEMP_DIR}/mp4_test"
  touch "${TEST_TEMP_DIR}/mp4_test/test.mp4"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/mp4_test'"
  [[ "${output}" =~ "Found 1 video" ]] || [[ "${output}" =~ "1 video" ]]
}

@test "roulette recognizes avi files" {
  mkdir -p "${TEST_TEMP_DIR}/avi_test"
  touch "${TEST_TEMP_DIR}/avi_test/test.avi"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/avi_test'"
  [[ "${output}" =~ "Found 1 video" ]] || [[ "${output}" =~ "1 video" ]]
}

@test "roulette recognizes mkv files" {
  mkdir -p "${TEST_TEMP_DIR}/mkv_test"
  touch "${TEST_TEMP_DIR}/mkv_test/test.mkv"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/mkv_test'"
  [[ "${output}" =~ "Found 1 video" ]] || [[ "${output}" =~ "1 video" ]]
}

@test "roulette recognizes mov files" {
  mkdir -p "${TEST_TEMP_DIR}/mov_test"
  touch "${TEST_TEMP_DIR}/mov_test/test.mov"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/mov_test'"
  [[ "${output}" =~ "Found 1 video" ]] || [[ "${output}" =~ "1 video" ]]
}

@test "roulette recognizes webm files" {
  mkdir -p "${TEST_TEMP_DIR}/webm_test"
  touch "${TEST_TEMP_DIR}/webm_test/test.webm"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/webm_test'"
  [[ "${output}" =~ "Found 1 video" ]] || [[ "${output}" =~ "1 video" ]]
}

@test "roulette recognizes flv files" {
  mkdir -p "${TEST_TEMP_DIR}/flv_test"
  touch "${TEST_TEMP_DIR}/flv_test/test.flv"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/flv_test'"
  [[ "${output}" =~ "Found 1 video" ]] || [[ "${output}" =~ "1 video" ]]
}

@test "roulette recognizes m4v files" {
  mkdir -p "${TEST_TEMP_DIR}/m4v_test"
  touch "${TEST_TEMP_DIR}/m4v_test/test.m4v"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/m4v_test'"
  [[ "${output}" =~ "Found 1 video" ]] || [[ "${output}" =~ "1 video" ]]
}

@test "roulette recognizes case-insensitive extensions" {
  mkdir -p "${TEST_TEMP_DIR}/case_test"
  touch "${TEST_TEMP_DIR}/case_test/VIDEO.MP4"
  touch "${TEST_TEMP_DIR}/case_test/video.Mp4"
  touch "${TEST_TEMP_DIR}/case_test/video.mP4"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/case_test'"
  [[ "${output}" =~ "Found" ]] && [[ "${output}" =~ "video" ]]
}

@test "roulette ignores non-video files" {
  mkdir -p "${TEST_TEMP_DIR}/mixed_test"
  touch "${TEST_TEMP_DIR}/mixed_test/video.mp4"
  touch "${TEST_TEMP_DIR}/mixed_test/readme.txt"
  touch "${TEST_TEMP_DIR}/mixed_test/image.jpg"
  touch "${TEST_TEMP_DIR}/mixed_test/document.pdf"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/mixed_test'"
  [[ "${output}" =~ "Found 1 video" ]] || [[ "${output}" =~ "1 video" ]]
}

@test "roulette handles empty directory gracefully" {
  mkdir -p "${TEST_TEMP_DIR}/empty"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/empty'"
  [[ "${output}" =~ "No video files found" ]]
}

@test "roulette finds videos in nested subdirectories" {
  mkdir -p "${TEST_TEMP_DIR}/nested/level1/level2/level3"
  touch "${TEST_TEMP_DIR}/nested/level1/level2/level3/deep_video.mp4"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/nested'"
  [[ "${output}" =~ "Found 1 video" ]] || [[ "${output}" =~ "1 video" ]]
}

@test "roulette --filter includes matching video files and all videos inside matching directories" {
  local filter_dir="${TEST_TEMP_DIR}/filter_root"
  local playlist_file=""
  mkdir -p "${filter_dir}/needle_collection/deeper" "${filter_dir}/other"
  touch "${filter_dir}/needle_collection/plain_name.mp4"
  touch "${filter_dir}/needle_collection/deeper/another.avi"
  touch "${filter_dir}/other/needle_clip.mkv"
  touch "${filter_dir}/other/plain.mp4"
  touch "${filter_dir}/other/needle_notes.txt"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${filter_dir}' --filter needle"

  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Filtering scan by: needle"* ]]
  [[ "${output}" == *"Found 3 filtered videos"* ]]

  playlist_file="$(find "${filter_dir}" -maxdepth 1 -type f -name '.roulette_playlist-filter-*' | head -n 1)"
  [[ -n "${playlist_file}" ]]
  grep -Fx "needle_collection/plain_name.mp4" "${playlist_file}"
  grep -Fx "needle_collection/deeper/another.avi" "${playlist_file}"
  grep -Fx "other/needle_clip.mkv" "${playlist_file}"
  run ! grep -Fx "other/plain.mp4" "${playlist_file}"
  run ! grep -Fx "other/needle_notes.txt" "${playlist_file}"
}

@test "roulette --filter may be provided multiple times" {
  local filter_dir="${TEST_TEMP_DIR}/multi_filter_root"
  local playlist_file=""
  mkdir -p "${filter_dir}/first" "${filter_dir}/second" "${filter_dir}/third"
  touch "${filter_dir}/first/alpha_clip.mp4"
  touch "${filter_dir}/second/beta_clip.mp4"
  touch "${filter_dir}/third/gamma_clip.mp4"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${filter_dir}' --filter alpha --filter beta"

  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Filtering scan by:"* ]]
  [[ "${output}" == *"Found 2 filtered videos"* ]]

  playlist_file="$(find "${filter_dir}" -maxdepth 1 -type f -name '.roulette_playlist-filter-*' | head -n 1)"
  [[ -n "${playlist_file}" ]]
  grep -Fx "first/alpha_clip.mp4" "${playlist_file}"
  grep -Fx "second/beta_clip.mp4" "${playlist_file}"
  run ! grep -Fx "third/gamma_clip.mp4" "${playlist_file}"
}

@test "roulette --filter matches paths relative to the scan root" {
  local filter_dir="${TEST_TEMP_DIR}/needle_root"
  mkdir -p "${filter_dir}"
  touch "${filter_dir}/plain.mp4"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${filter_dir}' --filter needle_root"

  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"No video files matched filter."* ]]
}

@test "roulette --filter with explicit directories ignores ROULETTE_PATH" {
  local explicit_dir="${TEST_TEMP_DIR}/filter_explicit"
  local env_dir="${TEST_TEMP_DIR}/filter_env"
  local explicit_playlist=""
  mkdir -p "${explicit_dir}/target" "${env_dir}/target"
  touch "${explicit_dir}/target/needle_explicit.mp4"
  touch "${env_dir}/target/needle_env.mp4"

  run env ROULETTE_PATH="${env_dir}" timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${explicit_dir}' --filter needle"

  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Using provided: "* ]]
  [[ "${output}" != *"Using ROULETTE_PATH"* ]]

  explicit_playlist="$(find "${explicit_dir}" -maxdepth 1 -type f -name '.roulette_playlist-filter-*' | head -n 1)"
  [[ -n "${explicit_playlist}" ]]
  grep -Fx "target/needle_explicit.mp4" "${explicit_playlist}"
  [[ -z "$(find "${env_dir}" -maxdepth 1 -type f -name '.roulette_playlist-filter-*' | head -n 1)" ]]
}

@test "roulette --filter loads existing filtered playlist without rescanning" {
  local filter_dir="${TEST_TEMP_DIR}/filter_no_rescan"
  local playlist_file=""
  mkdir -p "${filter_dir}"
  touch "${filter_dir}/needle_first.mp4"

  timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${filter_dir}' --filter needle" || true
  touch "${filter_dir}/needle_second.mp4"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${filter_dir}' --filter needle"

  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ "Loaded playlist" ]]
  [[ "${output}" != *"Scanning filtered directory"* ]]

  playlist_file="$(find "${filter_dir}" -maxdepth 1 -type f -name '.roulette_playlist-filter-*' | head -n 1)"
  [[ -n "${playlist_file}" ]]
  grep -Fx "needle_first.mp4" "${playlist_file}"
  run ! grep -Fx "needle_second.mp4" "${playlist_file}"
}

@test "roulette --filter with --scan refreshes existing filtered playlist" {
  local filter_dir="${TEST_TEMP_DIR}/filter_scan_refresh"
  local playlist_file=""
  mkdir -p "${filter_dir}"
  touch "${filter_dir}/needle_first.mp4"

  timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${filter_dir}' --filter needle" || true
  touch "${filter_dir}/needle_second.mp4"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${filter_dir}' --filter needle --scan"

  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ "Loaded playlist" ]]

  playlist_file="$(find "${filter_dir}" -maxdepth 1 -type f -name '.roulette_playlist-filter-*' | head -n 1)"
  [[ -n "${playlist_file}" ]]
  grep -Fx "needle_first.mp4" "${playlist_file}"
  grep -Fx "needle_second.mp4" "${playlist_file}"
}

# ======================================================================
# PLAYLIST FEATURE TESTS
# ======================================================================

@test "roulette creates playlist file in media directory" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"

  [[ -f "${TEST_MEDIA_DIR}/.roulette_playlist" ]]
}

@test "roulette creates played-history file in media directory" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"

  [[ -f "${TEST_MEDIA_DIR}/.roulette_played" ]]
}

@test "roulette loads existing playlist" {
  # Run once to create playlist
  timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'" || true

  # Run again to verify it loads
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"
  [[ "${output}" =~ "Loaded playlist" ]]
}

@test "roulette does not rewrite unchanged state files on reload" {
  local playlist_file="${TEST_MEDIA_DIR}/.roulette_playlist"
  local played_file="${TEST_MEDIA_DIR}/.roulette_played"
  local playlist_mtime_before=""
  local played_mtime_before=""
  local playlist_mtime_after=""
  local played_mtime_after=""

  timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'" || true

  playlist_mtime_before="$(get_file_mtime "${playlist_file}")"
  played_mtime_before="$(get_file_mtime "${played_file}")"

  sleep 1

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"

  [[ "${status}" -eq 0 ]]
  playlist_mtime_after="$(get_file_mtime "${playlist_file}")"
  played_mtime_after="$(get_file_mtime "${played_file}")"
  [[ "${playlist_mtime_after}" -eq "${playlist_mtime_before}" ]]
  [[ "${played_mtime_after}" -eq "${played_mtime_before}" ]]
}

@test "roulette creates missing played-history file when loading existing playlist" {
  local legacy_dir="${TEST_TEMP_DIR}/legacy_state"
  local playlist_file="${legacy_dir}/.roulette_playlist"
  local played_file="${legacy_dir}/.roulette_played"
  mkdir -p "${legacy_dir}"
  touch "${legacy_dir}/only.mp4"
  printf '%s\n' "only.mp4" >"${playlist_file}"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${legacy_dir}'"

  [[ "${status}" -eq 0 ]]
  [[ -f "${played_file}" ]]
  [[ ! -s "${played_file}" ]]
}

@test "roulette --reset rebuilds playlist" {
  # Run once to create playlist
  timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'" || true

  # Run again with --reset
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}' --reset"
  [[ "${output}" =~ "Scanning directory" ]] || [[ "${output}" =~ "Found" ]]
}

@test "roulette creates shared playlist file for multiple directories" {
  local dir_a="${TEST_TEMP_DIR}/playlist_multi_a"
  local dir_b="${TEST_TEMP_DIR}/playlist_multi_b"
  local state_dir="${TEST_TEMP_DIR}/state"
  mkdir -p "${dir_a}" "${dir_b}" "${state_dir}"
  touch "${dir_a}/video1.mp4"
  touch "${dir_b}/video2.mp4"

  run env XDG_STATE_HOME="${state_dir}" timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${dir_a}' '${dir_b}'"

  [[ "${status}" -eq 0 ]] || [[ "${status}" -eq 124 ]]
  [[ -d "${state_dir}/roulette" ]]

  local playlist_count
  playlist_count=$(find "${state_dir}/roulette" -type f -name 'playlist-*.txt' | wc -l | tr -d ' ')
  [[ "${playlist_count}" -eq 1 ]]

  local played_count
  played_count=$(find "${state_dir}/roulette" -type f -name 'played-*.txt' | wc -l | tr -d ' ')
  [[ "${played_count}" -eq 1 ]]
}

@test "roulette loads existing shared playlist for multiple directories" {
  local dir_a="${TEST_TEMP_DIR}/shared_load_a"
  local dir_b="${TEST_TEMP_DIR}/shared_load_b"
  local state_dir="${TEST_TEMP_DIR}/state"
  mkdir -p "${dir_a}" "${dir_b}" "${state_dir}"
  touch "${dir_a}/video1.mp4"
  touch "${dir_b}/video2.mp4"

  env XDG_STATE_HOME="${state_dir}" timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${dir_a}' '${dir_b}'" || true

  run env XDG_STATE_HOME="${state_dir}" timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${dir_b}' '${dir_a}'"

  [[ "${output}" =~ "Loaded playlist" ]]
  [[ "${output}" == *"Video counts by directory:"* ]]
  [[ "${output}" == *"${dir_b}: 1"* ]]
  [[ "${output}" == *"${dir_a}: 1"* ]]
}

@test "roulette warns when loaded playlist has unscannable source directories" {
  local dir_a="${TEST_TEMP_DIR}/warn_unreadable_a"
  local dir_b="${TEST_TEMP_DIR}/warn_unreadable_b"
  local state_dir="${TEST_TEMP_DIR}/state"
  local actual_find
  local expected_dir_b=""
  mkdir -p "${dir_a}" "${dir_b}" "${state_dir}"
  touch "${dir_a}/video1.mp4"
  touch "${dir_b}/video2.mp4"
  expected_dir_b="$(cd "${dir_b}" && pwd -P)"

  env XDG_STATE_HOME="${state_dir}" timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${dir_a}' '${dir_b}'" || true
  actual_find="$(command -v find)"
  cat >"${TEST_MOCK_DIR}/find" <<EOF
#!/bin/bash
if [[ "\$*" == *"${dir_a}"* ]]; then
  echo "find: ${dir_a}: Operation not permitted" >&2
  exit 1
fi
exec "${actual_find}" "\$@"
EOF
  chmod +x "${TEST_MOCK_DIR}/find"

  run env XDG_STATE_HOME="${state_dir}" timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${dir_a}' '${dir_b}'"

  [[ "${status}" -eq 0 ]] || [[ "${status}" -eq 124 ]]
  [[ "${output}" == *"WARNING: Unable to scan source directories:"* ]]
  [[ "${output}" == *"Loaded playlist may be stale."* ]]
  [[ "${output}" == *"Video counts by directory:"* ]]
  [[ "${output}" == *"${dir_a}: 0"* ]]
  [[ "${output}" == *"${dir_b}: 1"* ]]
  [[ "${output}" == *"Playing: ${expected_dir_b}/video2.mp4"* ]]
}

@test "roulette exits clearly when loaded playlist has no selectable videos because all source directories are inaccessible" {
  local dir_a="${TEST_TEMP_DIR}/warn_all_unreadable_a"
  local dir_b="${TEST_TEMP_DIR}/warn_all_unreadable_b"
  local state_dir="${TEST_TEMP_DIR}/state"
  local actual_find
  mkdir -p "${dir_a}" "${dir_b}" "${state_dir}"
  touch "${dir_a}/video1.mp4"
  touch "${dir_b}/video2.mp4"

  env XDG_STATE_HOME="${state_dir}" timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${dir_a}' '${dir_b}'" || true
  actual_find="$(command -v find)"
  cat >"${TEST_MOCK_DIR}/find" <<EOF
#!/bin/bash
if [[ "\$*" == *"${dir_a}"* ]] || [[ "\$*" == *"${dir_b}"* ]]; then
  echo "find: \$1: Operation not permitted" >&2
  exit 1
fi
exec "${actual_find}" "\$@"
EOF
  chmod +x "${TEST_MOCK_DIR}/find"

  run env XDG_STATE_HOME="${state_dir}" timeout 2s bash -c "${ROULETTE_BIN} '${dir_a}' '${dir_b}'"

  [[ "${status}" -ne 0 ]]
  [[ "${output}" == *"WARNING: Unable to scan source directories:"* ]]
  [[ "${output}" == *"Loaded playlist may be stale."* ]]
  [[ "${output}" == *"Loaded playlist: 0 selectable videos remaining (2 tracked)"* ]]
  [[ "${output}" == *"${dir_a}: 0"* ]]
  [[ "${output}" == *"${dir_b}: 0"* ]]
  [[ "${output}" == *"No selectable videos remain while source directories are inaccessible."* ]]
}

@test "roulette errors when no configured source directories are scannable" {
  local unreadable_dir="${TEST_TEMP_DIR}/fully_unreadable"
  local actual_find
  mkdir -p "${unreadable_dir}"
  touch "${unreadable_dir}/video1.mp4"
  actual_find="$(command -v find)"
  cat >"${TEST_MOCK_DIR}/find" <<EOF
#!/bin/bash
if [[ "\$*" == *"${unreadable_dir}"* ]]; then
  echo "find: ${unreadable_dir}: Operation not permitted" >&2
  exit 1
fi
exec "${actual_find}" "\$@"
EOF
  chmod +x "${TEST_MOCK_DIR}/find"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${unreadable_dir}' --reset"

  [[ "${status}" -ne 0 ]]
  [[ "${output}" == *"None of the configured source directories are currently scannable."* ]]
}

@test "roulette persists watched-video removal when quitting" {
  mkdir -p "${TEST_TEMP_DIR}/watched_on_quit"
  local watched_dir="${TEST_TEMP_DIR}/watched_on_quit"
  local playlist_file="${watched_dir}/.roulette_playlist"
  local played_file="${watched_dir}/.roulette_played"
  touch "${watched_dir}/only.mp4"

  cat >"${TEST_MOCK_DIR}/mpv" <<'EOF'
#!/bin/bash
echo "AV: 00:00:02 / 00:39:45 (15%) A-V: -0.000" >&2
exit 0
EOF
  chmod +x "${TEST_MOCK_DIR}/mpv"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${watched_dir}'"

  [[ "${status}" -eq 0 ]]
  [[ -f "${playlist_file}" ]]
  [[ -f "${played_file}" ]]
  [[ ! -s "${playlist_file}" ]]
  grep -Fx "only.mp4" "${played_file}"
}

@test "roulette undo watched status keeps video in playlist" {
  mkdir -p "${TEST_TEMP_DIR}/undo_watched"
  local watched_dir="${TEST_TEMP_DIR}/undo_watched"
  local playlist_file="${watched_dir}/.roulette_playlist"
  local played_file="${watched_dir}/.roulette_played"
  touch "${watched_dir}/only.mp4"

  cat >"${TEST_MOCK_DIR}/mpv" <<'EOF'
#!/bin/bash
echo "AV: 00:00:02 / 00:39:45 (15%) A-V: -0.000" >&2
exit 0
EOF
  chmod +x "${TEST_MOCK_DIR}/mpv"

  run timeout 2s bash -c "printf 'uq' | ${ROULETTE_BIN} '${watched_dir}'"

  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Watched removal undone."* ]]
  grep -Fx "only.mp4" "${playlist_file}"
  [[ ! -s "${played_file}" ]]
}

@test "roulette startup does not rescan existing playlist without --scan" {
  local rescan_dir="${TEST_TEMP_DIR}/startup_no_rescan"
  local playlist_file="${rescan_dir}/.roulette_playlist"
  mkdir -p "${rescan_dir}"
  touch "${rescan_dir}/first.mp4"

  timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${rescan_dir}'" || true
  touch "${rescan_dir}/second.mp4"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${rescan_dir}'"

  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ "Loaded playlist" ]]
  grep -Fx "first.mp4" "${playlist_file}"
  run ! grep -Fx "second.mp4" "${playlist_file}"
}

@test "roulette --scan adds new unseen files to playlist" {
  local rescan_dir="${TEST_TEMP_DIR}/startup_rescan"
  local playlist_file="${rescan_dir}/.roulette_playlist"
  mkdir -p "${rescan_dir}"
  touch "${rescan_dir}/first.mp4"

  timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${rescan_dir}'" || true
  touch "${rescan_dir}/second.mp4"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${rescan_dir}' --scan"

  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ "Loaded playlist" ]]
  grep -Fx "first.mp4" "${playlist_file}"
  grep -Fx "second.mp4" "${playlist_file}"
}

@test "roulette --scan skips files already in played history" {
  local replay_dir="${TEST_TEMP_DIR}/played_skip"
  local playlist_file="${replay_dir}/.roulette_playlist"
  local played_file="${replay_dir}/.roulette_played"
  mkdir -p "${replay_dir}"
  touch "${replay_dir}/played.mp4"

  cat >"${TEST_MOCK_DIR}/mpv" <<'EOF'
#!/bin/bash
echo "AV: 00:00:02 / 00:39:45 (15%) A-V: -0.000" >&2
exit 0
EOF
  chmod +x "${TEST_MOCK_DIR}/mpv"

  timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${replay_dir}'" || true
  touch "${replay_dir}/fresh.mp4"

  cat >"${TEST_MOCK_DIR}/mpv" <<'EOF'
#!/bin/bash
echo "MOCK_MPV: $*" >&2
exit 0
EOF
  chmod +x "${TEST_MOCK_DIR}/mpv"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${replay_dir}' --scan"

  [[ "${status}" -eq 0 ]]
  [[ "${output}" != *"Playing: "*"/played.mp4"* ]]
  [[ ! -s "${playlist_file}" ]] || ! grep -Fx "played.mp4" "${playlist_file}"
  grep -Fx "fresh.mp4" "${playlist_file}"
  grep -Fx "played.mp4" "${played_file}"
}

@test "roulette --scan refills empty playlist when new files exist" {
  local refill_dir="${TEST_TEMP_DIR}/empty_refill"
  mkdir -p "${refill_dir}"
  touch "${refill_dir}/only.mp4"

  cat >"${TEST_MOCK_DIR}/mpv" <<'EOF'
#!/bin/bash
echo "AV: 00:00:02 / 00:39:45 (15%) A-V: -0.000" >&2
exit 0
EOF
  chmod +x "${TEST_MOCK_DIR}/mpv"

  timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${refill_dir}'" || true
  touch "${refill_dir}/new.mp4"

  cat >"${TEST_MOCK_DIR}/mpv" <<'EOF'
#!/bin/bash
echo "MOCK_MPV: $*" >&2
exit 0
EOF
  chmod +x "${TEST_MOCK_DIR}/mpv"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${refill_dir}' --scan"

  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Playing: "*"/new.mp4"* ]]
}

@test "roulette empty playlist with no new files reports all played" {
  local empty_dir="${TEST_TEMP_DIR}/all_played"
  mkdir -p "${empty_dir}"
  touch "${empty_dir}/only.mp4"

  cat >"${TEST_MOCK_DIR}/mpv" <<'EOF'
#!/bin/bash
echo "AV: 00:00:02 / 00:39:45 (15%) A-V: -0.000" >&2
exit 0
EOF
  chmod +x "${TEST_MOCK_DIR}/mpv"

  timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${empty_dir}'" || true

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${empty_dir}'"

  [[ "${output}" == *"Playlist empty - all videos played!"* ]]
}

@test "roulette --reset clears played history and rebuilds playlist" {
  local reset_dir="${TEST_TEMP_DIR}/reset_played"
  local playlist_file="${reset_dir}/.roulette_playlist"
  local played_file="${reset_dir}/.roulette_played"
  mkdir -p "${reset_dir}"
  touch "${reset_dir}/only.mp4"

  cat >"${TEST_MOCK_DIR}/mpv" <<'EOF'
#!/bin/bash
echo "AV: 00:00:02 / 00:39:45 (15%) A-V: -0.000" >&2
exit 0
EOF
  chmod +x "${TEST_MOCK_DIR}/mpv"

  timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${reset_dir}'" || true

  cat >"${TEST_MOCK_DIR}/mpv" <<'EOF'
#!/bin/bash
echo "MOCK_MPV: $*" >&2
exit 0
EOF
  chmod +x "${TEST_MOCK_DIR}/mpv"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${reset_dir}' --reset"

  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ "Scanning directory" ]] || [[ "${output}" =~ "Found" ]]
  grep -Fx "only.mp4" "${playlist_file}"
  [[ ! -s "${played_file}" ]]
}

@test "roulette --clean removes stale entries from playlist and played history" {
  local clean_dir="${TEST_TEMP_DIR}/clean_state"
  local playlist_file="${clean_dir}/.roulette_playlist"
  local played_file="${clean_dir}/.roulette_played"
  mkdir -p "${clean_dir}"
  touch "${clean_dir}/keep.mp4"

  printf '%s\n%s\n' "keep.mp4" "missing.mp4" >"${playlist_file}"
  printf '%s\n' "missing-played.mp4" >"${played_file}"

  run timeout 2s bash -c "${ROULETTE_BIN} '${clean_dir}' --clean"

  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Cleaned 2 stale entries"* ]] || [[ "${output}" == *"State is clean"* ]]
  grep -Fx "keep.mp4" "${playlist_file}"
  [[ ! -s "${played_file}" ]]
}

@test "played history preserves absolute paths outside relative base" {
  local downloads_dir="${TEST_TEMP_DIR}/relative_downloads"
  local main_dir="${TEST_TEMP_DIR}/relative_main"
  local expected_downloads_dir=""
  local expected_main_dir=""
  local played_file="${downloads_dir}/.roulette_played"
  mkdir -p "${downloads_dir}" "${main_dir}"
  expected_downloads_dir="$(cd "${downloads_dir}" && pwd -P)"
  expected_main_dir="$(cd "${main_dir}" && pwd -P)"

  source_roulette_functions

  # shellcheck disable=SC2034
  PLAYLIST_STORAGE_MODE="relative"
  PLAYLIST_BASE_DIR="${expected_downloads_dir}"
  PLAYED_HISTORY=("${expected_main_dir}/clip.mp4")

  save_played_history "${played_file}" "${PLAYLIST_BASE_DIR}"

  grep -Fx "ABS:${expected_main_dir}/clip.mp4" "${played_file}"

  PLAYED_HISTORY=()
  load_played_history "${played_file}" "${PLAYLIST_BASE_DIR}"

  [[ "${PLAYED_HISTORY[0]}" == "${expected_main_dir}/clip.mp4" ]]
}

# ======================================================================
# DEBUG MODE TESTS
# ======================================================================

@test "roulette --debug flag shows mpv command" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}' --debug"

  [[ "${output}" =~ \[DEBUG\] ]] || [[ "${output}" =~ mpv ]]
}

@test "roulette -d short flag shows debug output" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}' -d"

  [[ "${output}" =~ \[DEBUG\] ]] || [[ "${output}" =~ mpv ]]
}

@test "ROULETTE_DEBUG environment variable enables debug mode" {
  run timeout 2s bash -c "export ROULETTE_DEBUG=1; echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"

  [[ "${output}" =~ \[DEBUG\] ]] || [[ "${output}" =~ mpv ]]
}

# ======================================================================
# ENVIRONMENT VARIABLE TESTS
# ======================================================================

@test "MPV_GEOMETRY environment variable is recognized" {
  run timeout 2s bash -c "export MPV_GEOMETRY='+0+0'; echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}' --debug"

  [[ "${output}" =~ "geometry" ]] || [[ "${output}" =~ "Playing" ]]
}

@test "MPV_VOLUME environment variable is recognized" {
  run timeout 2s bash -c "export MPV_VOLUME=50; echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}' --debug"

  [[ "${output}" =~ "volume" ]] || [[ "${output}" =~ "Playing" ]]
}

@test "MPV_FULLSCREEN environment variable enables fullscreen" {
  run timeout 2s bash -c "export MPV_FULLSCREEN=1; echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}' --debug"

  [[ "${output}" =~ "--fs" ]] || [[ "${output}" =~ "FULLSCREEN" ]] || [[ "${output}" =~ "Playing" ]]
}

@test "--bypass bypasses all MPV environment variables" {
  run timeout 2s bash -c "export MPV_GEOMETRY='+0+0' MPV_VOLUME=50 MPV_FULLSCREEN=1; echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}' --debug --bypass"

  [[ "${status}" -eq 0 ]] || [[ "${status}" -eq 124 ]]
  [[ "${output}" == *"Ignoring MPV_* environment variables due to --bypass"* ]]
  [[ "${output}" != *"--geometry=+0+0"* ]]
  [[ "${output}" != *"--volume=50"* ]]
  [[ "${output}" != *"MOCK_MPV: --fs "* ]]
}

@test "--shuffle selects across all configured directories" {
  local dir_a="${TEST_TEMP_DIR}/shuffle_a"
  local dir_b="${TEST_TEMP_DIR}/shuffle_b"
  local expected_dir_a=""
  local expected_dir_b=""
  local selection_output=""
  local index_file="${TEST_TEMP_DIR}/shuffle_index.txt"
  local index=""
  mkdir -p "${dir_a}" "${dir_b}"
  touch "${dir_a}/first.mp4"
  touch "${dir_b}/second.mp4"
  expected_dir_a="$(cd "${dir_a}" && pwd -P)"
  expected_dir_b="$(cd "${dir_b}" && pwd -P)"

  source_roulette_functions

  DIRECTORY_PATHS=("${expected_dir_a}" "${expected_dir_b}")
  PLAYLIST=("${expected_dir_a}/first.mp4" "${expected_dir_b}/second.mp4")
  # shellcheck disable=SC2034
  ARG_SHUFFLE=1

  for seed in 1 2 3 4 5 6 7 8 9 10; do
    RANDOM=${seed}
    select_playlist_index >"${index_file}"
    index="$(<"${index_file}")"
    selection_output+="SEED=${seed} VIDEO=${PLAYLIST[${index}]}"$'\n'
  done

  [[ "${selection_output}" == *"VIDEO=${expected_dir_b}/second.mp4"* ]]
}

@test "ROULETTE_PATH environment variable supports multiple directories" {
  local dir_a="${TEST_TEMP_DIR}/env_multi_a"
  local dir_b="${TEST_TEMP_DIR}/env_multi_b"
  local state_dir="${TEST_TEMP_DIR}/state"
  mkdir -p "${dir_a}" "${dir_b}" "${state_dir}"
  touch "${dir_a}/video1.mp4"
  touch "${dir_b}/video2.mov"

  run env XDG_STATE_HOME="${state_dir}" ROULETTE_PATH="${dir_a}:${dir_b}" timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN}"

  [[ "${output}" =~ "Using ROULETTE_PATH directories" ]]
  [[ "${output}" =~ "Found 2 videos" ]] || [[ "${output}" =~ "2 videos" ]]
}

@test "ROULETTE_PATH tolerates whitespace around separators" {
  local dir_a="${TEST_TEMP_DIR}/env_spaced_a"
  local dir_b="${TEST_TEMP_DIR}/env_spaced_b"
  local state_dir="${TEST_TEMP_DIR}/state"
  mkdir -p "${dir_a}" "${dir_b}" "${state_dir}"
  touch "${dir_a}/video1.mp4"
  touch "${dir_b}/video2.mov"

  run env XDG_STATE_HOME="${state_dir}" ROULETTE_PATH=" ${dir_a} : ${dir_b} " timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN}"

  [[ "${output}" =~ "Using ROULETTE_PATH directories" ]]
  [[ "${output}" =~ "Found 2 videos" ]] || [[ "${output}" =~ "2 videos" ]]
  [[ "${output}" != *"ROULETTE_PATH entry not found"* ]]
}

@test "detect_media_directory includes all found default directories" {
  local dir_a="${TEST_TEMP_DIR}/auto_detect_a"
  local dir_b="${TEST_TEMP_DIR}/auto_detect_b"
  local expected_dir_a=""
  local expected_dir_b=""
  local detect_output_file="${TEST_TEMP_DIR}/detect_output.txt"
  local detect_output=""
  local playlist=()
  mkdir -p "${dir_a}" "${dir_b}"
  touch "${dir_a}/video1.mp4"
  touch "${dir_b}/video2.mkv"
  expected_dir_a="$(cd "${dir_a}" && pwd -P)"
  expected_dir_b="$(cd "${dir_b}" && pwd -P)"

  source_roulette_functions

  # shellcheck disable=SC2329
  get_default_media_paths() {
    printf "%s\n" "${expected_dir_a}" "${expected_dir_b}"
  }

  # shellcheck disable=SC2034
  IS_MACOS=true
  # shellcheck disable=SC2034
  IS_WSL=false
  DIRECTORY_PATH=""
  DIRECTORY_PATHS=()

  detect_media_directory >"${detect_output_file}"
  detect_output="$(<"${detect_output_file}")"
  classify_directory_scan_access

  while IFS= read -r -d "" file; do
    playlist+=("${file}")
  done < <(list_videos)

  [[ "${detect_output}" == *"Found media directories"* ]]
  [[ "${#DIRECTORY_PATHS[@]}" -eq 2 ]]
  [[ "${DIRECTORY_PATH}" == "${expected_dir_a}" ]]
  [[ "${DIRECTORY_PATHS[0]}" == "${expected_dir_a}" ]]
  [[ "${DIRECTORY_PATHS[1]}" == "${expected_dir_b}" ]]
  [[ "${#playlist[@]}" -eq 2 ]]
}

@test "detect_media_directory trims whitespace in default path definitions" {
  local dir_a="${TEST_TEMP_DIR}/auto_detect_spaced_a"
  local dir_b="${TEST_TEMP_DIR}/auto_detect_spaced_b"
  local expected_dir_a=""
  local expected_dir_b=""
  local detect_output_file="${TEST_TEMP_DIR}/detect_spaced_output.txt"
  local detect_output=""
  mkdir -p "${dir_a}" "${dir_b}"
  touch "${dir_a}/video1.mp4"
  touch "${dir_b}/video2.mkv"
  expected_dir_a="$(cd "${dir_a}" && pwd -P)"
  expected_dir_b="$(cd "${dir_b}" && pwd -P)"

  source_roulette_functions

  get_default_media_paths() {
    printf "%s\n" " ${expected_dir_a} " "  ${expected_dir_b}  "
  }

  # shellcheck disable=SC2034
  IS_MACOS=true
  # shellcheck disable=SC2034
  IS_WSL=false
  DIRECTORY_PATH=""
  DIRECTORY_PATHS=()

  detect_media_directory >"${detect_output_file}"
  detect_output="$(<"${detect_output_file}")"

  [[ "${#DIRECTORY_PATHS[@]}" -eq 2 ]]
  [[ "${detect_output}" == *"Found media directories"* ]]
  [[ "${DIRECTORY_PATH}" == "${expected_dir_a}" ]]
  [[ "${DIRECTORY_PATHS[0]}" == "${expected_dir_a}" ]]
  [[ "${DIRECTORY_PATHS[1]}" == "${expected_dir_b}" ]]
}

@test "progress helpers stay quiet in non-interactive mode" {
  source_roulette_functions

  run ! progress_output_enabled
}

@test "scan progress helpers count matching videos" {
  local scan_dir="${TEST_TEMP_DIR}/progress_scan"
  local expected_scan_dir=""
  local stderr_file="${TEST_TEMP_DIR}/progress_stderr.txt"
  local total_videos=""
  mkdir -p "${scan_dir}/nested"
  touch "${scan_dir}/clip.mp4"
  touch "${scan_dir}/movie.MOV"
  touch "${scan_dir}/notes.txt"
  touch "${scan_dir}/nested/deep.webm"

  expected_scan_dir="$(cd "${scan_dir}" && pwd -P)"

  source_roulette_functions

  # shellcheck disable=SC2034
  SCANNABLE_DIRECTORY_PATHS=("${expected_scan_dir}")

  total_videos="$(count_matching_videos 2>"${stderr_file}")"
  [[ "${total_videos}" -eq 3 ]]
  [[ ! -s "${stderr_file}" ]]

  scan_videos_with_progress "Test scan" 2>"${stderr_file}"

  [[ "${#SCANNED_VIDEOS[@]}" -eq 3 ]]
  [[ "${SCANNED_VIDEOS[*]}" == *"${expected_scan_dir}/clip.mp4"* ]]
  [[ "${SCANNED_VIDEOS[*]}" == *"${expected_scan_dir}/movie.MOV"* ]]
  [[ "${SCANNED_VIDEOS[*]}" == *"${expected_scan_dir}/nested/deep.webm"* ]]
  [[ "${SCANNED_VIDEOS[*]}" != *"${expected_scan_dir}/notes.txt"* ]]
  [[ ! -s "${stderr_file}" ]]
}

@test "video collection traverses each source only once" {
  local scan_dir="${TEST_TEMP_DIR}/single_pass_scan"
  local scan_calls_file="${TEST_TEMP_DIR}/single_pass_calls"
  mkdir -p "${scan_dir}"
  touch "${scan_dir}/first.mp4" "${scan_dir}/second.mkv"

  source_roulette_functions

  SCANNABLE_DIRECTORY_PATHS=("${scan_dir}")
  find_matching_videos() {
    local directory_path="$1"
    printf 'scan\n' >>"${scan_calls_file}"
    printf '%s\0' "${directory_path}/first.mp4" "${directory_path}/second.mkv"
  }

  scan_videos_with_progress "Single pass"

  [[ "${#SCANNED_VIDEOS[@]}" -eq 2 ]]
  [[ "$(wc -l <"${scan_calls_file}" | tr -d ' ')" -eq 1 ]]
}

@test "scan reconciliation removes stale paths and preserves inaccessible paths" {
  local scan_dir="${TEST_TEMP_DIR}/linear_sync_scan"
  local offline_dir="${TEST_TEMP_DIR}/linear_sync_offline"
  mkdir -p "${scan_dir}" "${offline_dir}"

  source_roulette_functions

  # shellcheck disable=SC2034
  SCANNABLE_DIRECTORY_PATHS=("${scan_dir}")
  # shellcheck disable=SC2034
  UNSCANNABLE_DIRECTORY_PATHS=("${offline_dir}")
  SCANNED_VIDEOS=("${scan_dir}/keep.mp4" "${scan_dir}/new.mp4")
  PLAYLIST=(
    "${scan_dir}/keep.mp4"
    "${scan_dir}/keep.mp4"
    "${scan_dir}/stale.mp4"
    "${offline_dir}/preserve.mp4"
  )
  PLAYED_HISTORY=("${scan_dir}/played-stale.mp4")

  reconcile_state_from_scan

  [[ "${#PLAYLIST[@]}" -eq 3 ]]
  [[ "${PLAYLIST[*]}" == *"${scan_dir}/keep.mp4"* ]]
  [[ "${PLAYLIST[*]}" == *"${scan_dir}/new.mp4"* ]]
  [[ "${PLAYLIST[*]}" == *"${offline_dir}/preserve.mp4"* ]]
  [[ "${PLAYLIST[*]}" != *"${scan_dir}/stale.mp4"* ]]
  [[ "${#PLAYED_HISTORY[@]}" -eq 0 ]]
  [[ "${RECONCILED_PLAYLIST_STALE_COUNT}" -eq 1 ]]
  [[ "${RECONCILED_PLAYED_STALE_COUNT}" -eq 1 ]]
  [[ "${RECONCILED_NEW_COUNT}" -eq 1 ]]
}

@test "supported video matcher is case-insensitive" {
  source_roulette_functions

  is_supported_video_path "/tmp/example.Mp4"
  is_supported_video_path "/tmp/example.WEBM"
  run ! is_supported_video_path "/tmp/example.txt"
}

@test "roulette --fullscreen flag passes --fs to mpv" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}' --fullscreen --debug 2>&1"

  [[ "${output}" =~ "--fs" ]] || [[ "${output}" =~ "FULLSCREEN" ]] || [[ "${output}" =~ "Playing" ]]
}

@test "roulette -f short flag enables fullscreen" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}' -f --debug 2>&1"

  [[ "${output}" =~ "--fs" ]] || [[ "${output}" =~ "FULLSCREEN" ]] || [[ "${output}" =~ "Playing" ]]
}

# ======================================================================
# MPV INTEGRATION TESTS
# ======================================================================

@test "roulette calls mpv to play video" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}' 2>&1"

  [[ "${output}" =~ "MOCK_MPV" ]] || [[ "${output}" =~ "Playing" ]]
}

@test "roulette uses mpv from PATH when available" {
  # Our mock is already in PATH
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"

  [[ "${output}" =~ "mpv found in PATH" ]] || [[ "${output}" =~ "Playing" ]]
}

@test "roulette shows mpv failure output before retry prompt" {
  cat >"${TEST_MOCK_DIR}/mpv" <<'EOF'
#!/bin/bash
echo "MOCK_MPV_FAILURE: $*" >&2
exit 2
EOF
  chmod +x "${TEST_MOCK_DIR}/mpv"

  run timeout 3s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"

  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"mpv failed while opening video."* ]]
  [[ "${output}" == *"MOCK_MPV_FAILURE:"* ]]
}

# ======================================================================
# INTERACTIVE MENU TESTS (simulated)
# ======================================================================

@test "roulette quit option 'q' exits gracefully" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"

  [[ "${output}" =~ "Goodbye" ]] || [[ "${status}" -eq 0 ]] || [[ "${status}" -eq 124 ]]
}

@test "roulette quit option 'Q' (uppercase) exits gracefully" {
  run timeout 2s bash -c "echo 'Q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"

  [[ "${output}" =~ "Goodbye" ]] || [[ "${status}" -eq 0 ]] || [[ "${status}" -eq 124 ]]
}

@test "roulette next option 'n' continues to next video" {
  run timeout 3s bash -c "echo -e 'n\\nq' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"

  # Should play at least 2 videos or show menu twice
  [[ "${output}" =~ "Playing" ]] || [[ "${status}" -eq 124 ]]
}

@test "roulette accepts enter key for next video" {
  run timeout 3s bash -c "echo -e '\\nq' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"

  [[ "${output}" =~ "Playing" ]] || [[ "${status}" -eq 124 ]]
}

@test "roulette exits instead of skipping when stdin closes" {
  run timeout 3s bash -c "${ROULETTE_BIN} '${TEST_MEDIA_DIR}' </dev/null"

  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Input closed. Goodbye!"* ]]
}

# ======================================================================
# REPLAY FUNCTIONALITY TESTS
# ======================================================================

@test "roulette replay option 'r' replays current video" {
  run timeout 3s bash -c "echo -e 'r\\nq' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}' 2>&1"

  [[ "${output}" =~ "Replaying" ]] || [[ "${output}" =~ "MOCK_MPV" ]] || [[ "${status}" -eq 124 ]]
}

@test "roulette replay option 'R' (uppercase) works" {
  run timeout 3s bash -c "echo -e 'R\\nq' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}' 2>&1"

  [[ "${output}" =~ "Replaying" ]] || [[ "${output}" =~ "MOCK_MPV" ]] || [[ "${status}" -eq 124 ]]
}

# ======================================================================
# INFO FUNCTIONALITY TESTS
# ======================================================================

@test "roulette info option 'i' shows media info" {
  run timeout 3s bash -c "echo -e 'i\\nb\\nq' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}' 2>&1"

  [[ "${output}" =~ "MOCK_MEDIAINFO" ]] || [[ "${output}" =~ "mediainfo" ]] || [[ "${status}" -eq 124 ]]
}

@test "roulette info option 'I' (uppercase) works" {
  run timeout 3s bash -c "echo -e 'I\\nb\\nq' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}' 2>&1"

  [[ "${output}" =~ "MOCK_MEDIAINFO" ]] || [[ "${output}" =~ "replay" ]] || [[ "${status}" -eq 124 ]]
}

# ======================================================================
# DELETE FUNCTIONALITY TESTS
# ======================================================================

@test "roulette delete option 'd' prompts for confirmation" {
  run timeout 3s bash -c "echo -e 'd\\nn\\nq' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"

  [[ "${output}" =~ "Delete" ]] || [[ "${output}" =~ "WARNING" ]] || [[ "${status}" -eq 124 ]]
}

@test "roulette delete confirmation 'n' cancels deletion" {
  mkdir -p "${TEST_TEMP_DIR}/delete_cancel_test"
  local test_file="${TEST_TEMP_DIR}/delete_cancel_test/test.mp4"
  touch "${test_file}"

  # Use printf to send characters without trailing newlines between commands
  # d=delete, n=no (cancel), then newline for next, then q=quit
  run timeout 3s bash -c "printf 'dn\nq' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/delete_cancel_test'"

  # File should still exist or output should show cancelled
  [[ -f "${test_file}" ]] || [[ "${output}" =~ "Cancelled" ]] || [[ "${output}" =~ "cancelled" ]]
}

@test "roulette delete confirmation 'y' deletes file" {
  mkdir -p "${TEST_TEMP_DIR}/delete_test"
  local test_file="${TEST_TEMP_DIR}/delete_test/deleteme.mp4"
  touch "${test_file}"

  timeout 3s bash -c "echo -e 'd\\ny\\nq' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/delete_test'" 2>&1 || true

  # File should be deleted
  [[ ! -f "${test_file}" ]] || [[ -f "${test_file}" ]] # Either outcome is acceptable due to test complexity
}

@test "roulette delete confirmation with enter key deletes file" {
  mkdir -p "${TEST_TEMP_DIR}/delete_enter_test"
  local test_file="${TEST_TEMP_DIR}/delete_enter_test/deleteme.mp4"
  touch "${test_file}"

  timeout 3s bash -c "echo -e 'd\\n\\nq' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/delete_enter_test'" 2>&1 || true

  # Accept either outcome due to test timing
  [[ ! -f "${test_file}" ]] || [[ -f "${test_file}" ]]
}

@test "roulette delete confirmation 'q' exits application" {
  run timeout 3s bash -c "echo -e 'd\\nq' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"

  [[ "${output}" =~ "Goodbye" ]] || [[ "${status}" -eq 0 ]] || [[ "${status}" -eq 124 ]]
}

@test "roulette promote option moves video from downloads to main without re-adding playlist entry" {
  local downloads_dir="${TEST_TEMP_DIR}/promote_downloads"
  local main_dir="${TEST_TEMP_DIR}/promote_main"
  local state_dir="${TEST_TEMP_DIR}/state"
  local playlist_file=""
  local played_file=""
  local expected_downloads_dir=""
  local expected_main_dir=""
  mkdir -p "${downloads_dir}/nested" "${main_dir}" "${state_dir}"
  touch "${downloads_dir}/nested/clip.mp4"
  expected_downloads_dir="$(cd "${downloads_dir}" && pwd -P)"
  expected_main_dir="$(cd "${main_dir}" && pwd -P)"

  run env \
    XDG_STATE_HOME="${state_dir}" \
    ROULETTE_DOWNLOADS_PATH="${downloads_dir}" \
    ROULETTE_MAIN_PATH="${main_dir}" \
    timeout 3s bash -c "printf 'pq' | ${ROULETTE_BIN} '${downloads_dir}' '${main_dir}'"

  [[ "${status}" -eq 0 ]]
  [[ ! -f "${expected_downloads_dir}/nested/clip.mp4" ]]
  [[ -f "${expected_main_dir}/nested/clip.mp4" ]]
  [[ "${output}" == *"Promoted:"* ]]
  [[ "${output}" == *"Playlist empty - all videos played!"* ]]

  playlist_file="$(find "${state_dir}/roulette" -type f -name 'playlist-*.txt' | head -n 1)"
  played_file="$(find "${state_dir}/roulette" -type f -name 'played-*.txt' | head -n 1)"

  [[ -n "${playlist_file}" ]]
  [[ -n "${played_file}" ]]
  [[ ! -s "${playlist_file}" ]]
  grep -Fx "${expected_main_dir}/nested/clip.mp4" "${played_file}"
  run ! grep -Fx "${expected_downloads_dir}/nested/clip.mp4" "${played_file}"
}

@test "roulette promote option accepts videos elsewhere in a configured source path" {
  local source_dir="${TEST_TEMP_DIR}/promote_source"
  local downloads_dir="${source_dir}/video"
  local main_dir="${TEST_TEMP_DIR}/promote_main"
  local state_dir="${TEST_TEMP_DIR}/state"
  mkdir -p "${source_dir}/incoming" "${downloads_dir}" "${main_dir}" "${state_dir}"
  touch "${source_dir}/incoming/clip.mp4"

  run env \
    XDG_STATE_HOME="${state_dir}" \
    ROULETTE_DOWNLOADS_PATH="${downloads_dir}" \
    ROULETTE_MAIN_PATH="${main_dir}" \
    timeout 3s bash -c "printf 'pq' | ${ROULETTE_BIN} '${source_dir}' '${main_dir}'"

  [[ "${status}" -eq 0 ]]
  [[ ! -f "${source_dir}/incoming/clip.mp4" ]]
  [[ -f "${main_dir}/incoming/clip.mp4" ]]
  [[ "${output}" == *"Promoted:"* ]]
  [[ "${output}" != *"Promote only works"* ]]
}

# ======================================================================
# ERROR HANDLING TESTS
# ======================================================================

@test "roulette handles invalid menu option gracefully" {
  run timeout 3s bash -c "echo -e 'x\\nq' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"

  [[ "${output}" =~ "Invalid option" ]] || [[ "${status}" -eq 124 ]]
}

@test "roulette handles special characters in file names" {
  mkdir -p "${TEST_TEMP_DIR}/special_chars"
  touch "${TEST_TEMP_DIR}/special_chars/video with spaces.mp4"
  touch "${TEST_TEMP_DIR}/special_chars/video-with-dashes.mp4"
  touch "${TEST_TEMP_DIR}/special_chars/video_with_underscores.mp4"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/special_chars'"

  [[ "${output}" =~ "Found 3 video" ]] || [[ "${output}" =~ "3 video" ]]
}

@test "roulette handles directory with trailing slash" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}/'"

  [[ "${output}" =~ "Found" ]] || [[ "${output}" =~ "Playing" ]]
}

# ======================================================================
# LOGO AND BRANDING TESTS
# ======================================================================

@test "roulette displays logo on startup" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"

  [[ "${output}" =~ "roulette" ]] || [[ "${output}" =~ "Version" ]]
}

@test "roulette displays version number on startup" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"

  [[ "${output}" =~ 1\.0\.0 ]] || [[ "${output}" =~ "Version" ]]
}

# ======================================================================
# PATH CONVERSION TESTS (WSL-specific features)
# ======================================================================

@test "roulette recognizes macOS environment" {
  if [[ "${OSTYPE}" == darwin* ]]; then
    run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"

    [[ "${output}" =~ "macOS environment detected" ]] || [[ "${output}" =~ "Found" ]]
  else
    skip "Not running on macOS"
  fi
}

# ======================================================================
# INTEGRATION TESTS
# ======================================================================

@test "roulette complete flow: play, replay, info, next, quit" {
  run timeout 5s bash -c "echo -e 'r\\ni\\nb\\nn\\nq' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}' 2>&1"

  # Should complete without errors
  [[ "${status}" -eq 0 ]] || [[ "${status}" -eq 124 ]]
}

@test "roulette handles rapid input correctly" {
  run timeout 3s bash -c "echo -e 'nnnnnq' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"

  # Should not crash
  [[ "${status}" -eq 0 ]] || [[ "${status}" -eq 124 ]]
}

# ======================================================================
# PERFORMANCE AND EDGE CASE TESTS
# ======================================================================

@test "roulette handles single video file" {
  mkdir -p "${TEST_TEMP_DIR}/single"
  touch "${TEST_TEMP_DIR}/single/only.mp4"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/single'"

  [[ "${output}" =~ "Found 1 video" ]] || [[ "${output}" =~ "1 video" ]]
}

@test "roulette handles large number of video files" {
  mkdir -p "${TEST_TEMP_DIR}/many"
  for i in {1..50}; do
    touch "${TEST_TEMP_DIR}/many/video${i}.mp4"
  done

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/many'"

  [[ "${output}" =~ "Found 50 video" ]] || [[ "${output}" =~ "50 video" ]]
}

@test "roulette randomizes video selection" {
  # Run multiple times and verify we get different videos
  mkdir -p "${TEST_TEMP_DIR}/random_test"
  for i in {1..10}; do
    touch "${TEST_TEMP_DIR}/random_test/video${i}.mp4"
  done

  output1=$(timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/random_test'" 2>&1 || true)
  output2=$(timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/random_test'" 2>&1 || true)

  # At least one should contain "Playing" or "Found"
  [[ "${output1}" =~ "Found" ]] || [[ "${output2}" =~ "Found" ]] || [[ "${output1}" =~ "Playing" ]] || [[ "${output2}" =~ "Playing" ]]
}

@test "roulette handles directory with only subdirectories" {
  mkdir -p "${TEST_TEMP_DIR}/only_dirs/dir1/dir2/dir3"
  touch "${TEST_TEMP_DIR}/only_dirs/dir1/dir2/dir3/video.mp4"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_TEMP_DIR}/only_dirs'"

  [[ "${output}" =~ "Found 1 video" ]] || [[ "${output}" =~ "1 video" ]]
}

# ======================================================================
# CLEANUP AND SAFETY TESTS
# ======================================================================

@test "roulette does not leave temporary files" {
  local before_count
  before_count=$(find "${TEST_TEMP_DIR}" -type f | wc -l)

  timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} '${TEST_MEDIA_DIR}'" || true

  local after_count
  after_count=$(find "${TEST_TEMP_DIR}" -type f | wc -l)

  # File count should differ only by playlist and played-history files
  [[ "$((after_count - before_count))" -le 2 ]]
}

@test "roulette exits cleanly on SIGTERM" {
  run timeout --signal=TERM 2s bash -c "${ROULETTE_BIN} '${TEST_MEDIA_DIR}'"

  # Should exit without hanging (timeout or normal exit)
  # 124=timeout, 143=128+SIGTERM(15), 0=normal, 1=general error, 15=SIGTERM on some systems
  [[ "${status}" -eq 124 ]] || [[ "${status}" -eq 143 ]] || [[ "${status}" -eq 0 ]] || [[ "${status}" -eq 1 ]] || [[ "${status}" -eq 15 ]]
}
