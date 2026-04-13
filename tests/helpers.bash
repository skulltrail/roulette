#!/usr/bin/env bash
# BATS test helpers for roulette

# Create a mock executable in the test environment
create_mock_executable() {
  local name="$1"
  local script_content="$2"
  local mock_path="${TEST_MOCK_DIR}/${name}"

  echo "#!/bin/bash" >"${mock_path}"
  echo "${script_content}" >>"${mock_path}"
  chmod +x "${mock_path}"

  echo "${mock_path}"
}

# Create test video files with specific extensions
create_videos_with_extensions() {
  local dir="$1"
  shift
  local extensions=("$@")

  mkdir -p "${dir}"
  for ext in "${extensions[@]}"; do
    touch "${dir}/video.${ext}"
  done
}

# Count video files in directory (recursive)
count_video_files() {
  local dir="$1"
  find "${dir}" -type f \( \
    -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mkv" -o \
    -iname "*.mov" -o -iname "*.wmv" -o -iname "*.flv" -o \
    -iname "*.webm" -o -iname "*.m4v" -o -iname "*.mpg" -o \
    -iname "*.mpeg" \
    \) | wc -l | tr -d ' '
}

# Simulate user input for interactive prompts
simulate_input() {
  local inputs=("$@")
  for input in "${inputs[@]}"; do
    echo "${input}"
  done
}

# Wait for file to be created (with timeout)
wait_for_file() {
  local file="$1"
  local timeout="${2:-5}"
  local elapsed=0

  while [ ! -f "${file}" ] && [ "${elapsed}" -lt "${timeout}" ]; do
    sleep 0.1
    elapsed=$((elapsed + 1))
  done

  [ -f "${file}" ]
}

# Assert file contains string
assert_file_contains() {
  local file="$1"
  local string="$2"

  if [ ! -f "${file}" ]; then
    echo "File does not exist: ${file}" >&2
    return 1
  fi

  if ! grep -q "${string}" "${file}"; then
    echo "File does not contain: ${string}" >&2
    return 1
  fi

  return 0
}

# Assert output contains multiple strings
assert_output_contains_all() {
  local actual_output="$1"
  shift
  local expected_strings=("$@")

  for string in "${expected_strings[@]}"; do
    if [[ ! "${actual_output}" =~ ${string} ]]; then
      echo "Output missing: ${string}" >&2
      return 1
    fi
  done

  return 0
}

# Clean test environment
clean_test_env() {
  if [ -n "${TEST_TEMP_DIR}" ] && [ -d "${TEST_TEMP_DIR}" ]; then
    rm -rf "${TEST_TEMP_DIR}"
  fi
}

# Get random video from output
extract_played_video() {
  local output="$1"
  echo "${output}" | grep -o "Playing: .*" | sed 's/Playing: //' | head -n1
}

# Check if running on macOS
is_macos() {
  [[ "${OSTYPE}" == darwin* ]]
}

# Check if running on WSL
is_wsl() {
  [ -f /proc/version ] && grep -qEi "(Microsoft|WSL)" /proc/version
}

# Check if running on Linux
is_linux() {
  [[ "${OSTYPE}" == linux* ]] && ! is_wsl
}

# Create directory structure for testing
create_test_directory_tree() {
  local base_dir="$1"

  mkdir -p "${base_dir}"/{videos,archive/old,new/2024/jan}

  touch "${base_dir}/videos/video1.mp4"
  touch "${base_dir}/videos/video2.avi"
  touch "${base_dir}/archive/old/video3.mkv"
  touch "${base_dir}/archive/old/video4.mov"
  touch "${base_dir}/new/2024/jan/video5.webm"
}

# Verify played file format
verify_played_file_format() {
  local played_file="$1"

  if [ ! -f "${played_file}" ]; then
    return 1
  fi

  # Each line should be an absolute path
  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    [[ "${line}" == /* ]] || return 1
  done <"${played_file}"

  return 0
}
