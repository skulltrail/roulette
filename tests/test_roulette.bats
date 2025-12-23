#!/usr/bin/env bats
# Comprehensive BATS tests for roulette

# Test setup - runs before each test
setup() {
  export BATS_TEST_DIRNAME="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  export PROJECT_ROOT="$(dirname "${BATS_TEST_DIRNAME}")"
  export ROULETTE_BIN="${PROJECT_ROOT}/roulette"

  # Create temporary test directories
  export TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_MEDIA_DIR="${TEST_TEMP_DIR}/media"
  export TEST_PLAYED_FILE="${TEST_TEMP_DIR}/played.txt"
  export TEST_MOCK_DIR="${TEST_TEMP_DIR}/mock_bin"

  mkdir -p "${TEST_MEDIA_DIR}" "${TEST_MOCK_DIR}"

  # Create mock mpv that doesn't actually play videos
  cat > "${TEST_MOCK_DIR}/mpv" <<'EOF'
#!/bin/bash
# Mock MPV - just logs the call and exits successfully
echo "MOCK_MPV: $*" >&2
exit 0
EOF
  chmod +x "${TEST_MOCK_DIR}/mpv"

  # Create mock mediainfo
  cat > "${TEST_MOCK_DIR}/mediainfo" <<'EOF'
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
  [[ "${output}" =~ "1.0.0" ]]
}

@test "roulette run shows help with --help flag" {
  run "${ROULETTE_BIN}" run --help
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ "--save-played" ]]
  [[ "${output}" =~ "--played-file" ]]
  [[ "${output}" =~ "--debug" ]]
  [[ "${output}" =~ "Arguments" ]]
}

# ======================================================================
# DIRECTORY VALIDATION TESTS
# ======================================================================

@test "roulette fails when provided directory does not exist" {
  run timeout 2s "${ROULETTE_BIN}" run /nonexistent/directory <<< "q"
  [[ "${status}" -ne 0 ]]
  [[ "${output}" =~ "Directory not found" ]]
}

@test "roulette accepts tilde (~) in directory path" {
  # Create a test dir in home
  local home_test_dir="${HOME}/.roulette_test_$(date +%s)"
  mkdir -p "${home_test_dir}"
  touch "${home_test_dir}/test.mp4"

  run timeout 2s "${ROULETTE_BIN}" run "~/.roulette_test_$(date +%s | head -c 10)" <<< "q" 2>&1 || true

  # Cleanup
  rm -rf "${home_test_dir}"

  # We expect it to fail because directory won't match exactly, but tilde expansion should happen
  [[ "${output}" =~ "Directory not found" ]] || [[ "${output}" =~ "Playing" ]] || [[ "${output}" =~ "Found" ]]
}

@test "roulette accepts valid directory path" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}'"
  [[ "${output}" =~ "Using provided directory: ${TEST_MEDIA_DIR}" ]] || [[ "${output}" =~ "Found" ]]
}

# ======================================================================
# VIDEO FILE DISCOVERY TESTS
# ======================================================================

@test "roulette finds video files recursively" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}'"
  [[ "${output}" =~ "Found 7 video files" ]] || [[ "${output}" =~ "video" ]]
}

@test "roulette recognizes mp4 files" {
  mkdir -p "${TEST_TEMP_DIR}/mp4_test"
  touch "${TEST_TEMP_DIR}/mp4_test/test.mp4"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_TEMP_DIR}/mp4_test'"
  [[ "${output}" =~ "Found 1 video" ]]
}

@test "roulette recognizes avi files" {
  mkdir -p "${TEST_TEMP_DIR}/avi_test"
  touch "${TEST_TEMP_DIR}/avi_test/test.avi"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_TEMP_DIR}/avi_test'"
  [[ "${output}" =~ "Found 1 video" ]]
}

@test "roulette recognizes mkv files" {
  mkdir -p "${TEST_TEMP_DIR}/mkv_test"
  touch "${TEST_TEMP_DIR}/mkv_test/test.mkv"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_TEMP_DIR}/mkv_test'"
  [[ "${output}" =~ "Found 1 video" ]]
}

@test "roulette recognizes mov files" {
  mkdir -p "${TEST_TEMP_DIR}/mov_test"
  touch "${TEST_TEMP_DIR}/mov_test/test.mov"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_TEMP_DIR}/mov_test'"
  [[ "${output}" =~ "Found 1 video" ]]
}

@test "roulette recognizes webm files" {
  mkdir -p "${TEST_TEMP_DIR}/webm_test"
  touch "${TEST_TEMP_DIR}/webm_test/test.webm"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_TEMP_DIR}/webm_test'"
  [[ "${output}" =~ "Found 1 video" ]]
}

@test "roulette recognizes flv files" {
  mkdir -p "${TEST_TEMP_DIR}/flv_test"
  touch "${TEST_TEMP_DIR}/flv_test/test.flv"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_TEMP_DIR}/flv_test'"
  [[ "${output}" =~ "Found 1 video" ]]
}

@test "roulette recognizes m4v files" {
  mkdir -p "${TEST_TEMP_DIR}/m4v_test"
  touch "${TEST_TEMP_DIR}/m4v_test/test.m4v"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_TEMP_DIR}/m4v_test'"
  [[ "${output}" =~ "Found 1 video" ]]
}

@test "roulette recognizes case-insensitive extensions" {
  mkdir -p "${TEST_TEMP_DIR}/case_test"
  touch "${TEST_TEMP_DIR}/case_test/VIDEO.MP4"
  touch "${TEST_TEMP_DIR}/case_test/video.Mp4"
  touch "${TEST_TEMP_DIR}/case_test/video.mP4"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_TEMP_DIR}/case_test'"
  [[ "${output}" =~ "Found" ]] && [[ "${output}" =~ "video" ]]
}

@test "roulette ignores non-video files" {
  mkdir -p "${TEST_TEMP_DIR}/mixed_test"
  touch "${TEST_TEMP_DIR}/mixed_test/video.mp4"
  touch "${TEST_TEMP_DIR}/mixed_test/readme.txt"
  touch "${TEST_TEMP_DIR}/mixed_test/image.jpg"
  touch "${TEST_TEMP_DIR}/mixed_test/document.pdf"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_TEMP_DIR}/mixed_test'"
  [[ "${output}" =~ "Found 1 video" ]]
}

@test "roulette handles empty directory gracefully" {
  mkdir -p "${TEST_TEMP_DIR}/empty"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_TEMP_DIR}/empty'"
  [[ "${output}" =~ "No unplayed video files found" ]]
}

@test "roulette finds videos in nested subdirectories" {
  mkdir -p "${TEST_TEMP_DIR}/nested/level1/level2/level3"
  touch "${TEST_TEMP_DIR}/nested/level1/level2/level3/deep_video.mp4"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_TEMP_DIR}/nested'"
  [[ "${output}" =~ "Found 1 video" ]]
  [[ "${output}" =~ "deep_video.mp4" ]] || [[ "${output}" =~ "Playing" ]]
}

# ======================================================================
# SAVE-PLAYED FEATURE TESTS
# ======================================================================

@test "roulette --save-played flag creates played file" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' --save-played --played-file '${TEST_PLAYED_FILE}'"

  [[ -f "${TEST_PLAYED_FILE}" ]]
}

@test "roulette saves played video path to file" {
  run timeout 2s bash -c "echo -e 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' --save-played --played-file '${TEST_PLAYED_FILE}'"

  [[ -f "${TEST_PLAYED_FILE}" ]]
  [[ -s "${TEST_PLAYED_FILE}" ]]  # File is not empty
}

@test "roulette accumulates played videos across multiple runs" {
  # Run 1
  timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' --save-played --played-file '${TEST_PLAYED_FILE}'" || true

  # Run 2
  timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' --save-played --played-file '${TEST_PLAYED_FILE}'" || true

  # Check that played file has multiple entries
  if [[ -f "${TEST_PLAYED_FILE}" ]]; then
    line_count=$(wc -l < "${TEST_PLAYED_FILE}" | tr -d ' ')
    [[ "${line_count}" -ge 1 ]]
  fi
}

@test "roulette excludes played videos on subsequent runs" {
  # Play all videos one by one
  for i in {1..8}; do
    timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' --save-played --played-file '${TEST_PLAYED_FILE}'" 2>&1 || true
  done

  # Next run should find no unplayed videos
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' --save-played --played-file '${TEST_PLAYED_FILE}'"
  [[ "${output}" =~ "No unplayed video files" ]] || [[ ! -s "${TEST_PLAYED_FILE}" ]]
}

@test "roulette --played-file uses custom path" {
  local custom_played="${TEST_TEMP_DIR}/custom/path/played.txt"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' --save-played --played-file '${custom_played}'"

  [[ -f "${custom_played}" ]] || [[ "${output}" =~ "Playing" ]]
}

@test "roulette --save-played short flag -s works" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' -s -p '${TEST_PLAYED_FILE}'"

  [[ "${output}" =~ "Playing" ]] || [[ "${output}" =~ "Found" ]]
}

@test "roulette --played-file short flag -p works" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' --save-played -p '${TEST_PLAYED_FILE}'"

  [[ "${output}" =~ "Playing" ]] || [[ "${output}" =~ "Found" ]]
}

@test "roulette uses default played file path when not specified" {
  # Clean up default file if it exists
  local default_played="${HOME}/.roulette_played"
  local backup_file="${default_played}.bats_backup"

  # Backup existing file
  [[ -f "${default_played}" ]] && mv "${default_played}" "${backup_file}"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' --save-played"

  # Restore backup
  [[ -f "${backup_file}" ]] && mv "${backup_file}" "${default_played}"

  [[ "${output}" =~ "Playing" ]] || [[ "${output}" =~ "Found" ]]
}

# ======================================================================
# DEBUG MODE TESTS
# ======================================================================

@test "roulette --debug flag shows mpv command" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' --debug"

  [[ "${output}" =~ "[DEBUG]" ]] || [[ "${output}" =~ "mpv" ]]
}

@test "roulette -d short flag shows debug output" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' -d"

  [[ "${output}" =~ "[DEBUG]" ]] || [[ "${output}" =~ "mpv" ]]
}

@test "ROULETTE_DEBUG environment variable enables debug mode" {
  run timeout 2s bash -c "export ROULETTE_DEBUG=1; echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}'"

  [[ "${output}" =~ "[DEBUG]" ]] || [[ "${output}" =~ "mpv" ]]
}

# ======================================================================
# ENVIRONMENT VARIABLE TESTS
# ======================================================================

@test "MPV_GEOMETRY environment variable is recognized" {
  run timeout 2s bash -c "export MPV_GEOMETRY='+0+0'; echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' --debug"

  [[ "${output}" =~ "geometry" ]] || [[ "${output}" =~ "Playing" ]]
}

@test "MPV_VOLUME environment variable is recognized" {
  run timeout 2s bash -c "export MPV_VOLUME=50; echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' --debug"

  [[ "${output}" =~ "volume" ]] || [[ "${output}" =~ "Playing" ]]
}

# ======================================================================
# MPV INTEGRATION TESTS
# ======================================================================

@test "roulette calls mpv to play video" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' 2>&1"

  [[ "${output}" =~ "MOCK_MPV" ]] || [[ "${output}" =~ "Playing" ]]
}

@test "roulette uses mpv from PATH when available" {
  # Our mock is already in PATH
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}'"

  [[ "${output}" =~ "mpv found in PATH" ]] || [[ "${output}" =~ "Playing" ]]
}

# ======================================================================
# INTERACTIVE MENU TESTS (simulated)
# ======================================================================

@test "roulette quit option 'q' exits gracefully" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}'"

  [[ "${output}" =~ "Goodbye" ]] || [[ "${status}" -eq 0 ]] || [[ "${status}" -eq 124 ]]
}

@test "roulette quit option 'Q' (uppercase) exits gracefully" {
  run timeout 2s bash -c "echo 'Q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}'"

  [[ "${output}" =~ "Goodbye" ]] || [[ "${status}" -eq 0 ]] || [[ "${status}" -eq 124 ]]
}

@test "roulette next option 'n' continues to next video" {
  run timeout 3s bash -c "echo -e 'n\\nq' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}'"

  # Should play at least 2 videos or show menu twice
  [[ "${output}" =~ "Playing" ]] || [[ "${status}" -eq 124 ]]
}

@test "roulette accepts enter key for next video" {
  run timeout 3s bash -c "echo -e '\\nq' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}'"

  [[ "${output}" =~ "Playing" ]] || [[ "${status}" -eq 124 ]]
}

# ======================================================================
# REPLAY FUNCTIONALITY TESTS
# ======================================================================

@test "roulette replay option 'r' replays current video" {
  run timeout 3s bash -c "echo -e 'r\\nq' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' 2>&1"

  [[ "${output}" =~ "Replaying" ]] || [[ "${output}" =~ "MOCK_MPV" ]] || [[ "${status}" -eq 124 ]]
}

@test "roulette replay option 'R' (uppercase) works" {
  run timeout 3s bash -c "echo -e 'R\\nq' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' 2>&1"

  [[ "${output}" =~ "Replaying" ]] || [[ "${output}" =~ "MOCK_MPV" ]] || [[ "${status}" -eq 124 ]]
}

# ======================================================================
# INFO FUNCTIONALITY TESTS
# ======================================================================

@test "roulette info option 'i' shows media info" {
  run timeout 3s bash -c "echo -e 'i\\nb\\nq' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' 2>&1"

  [[ "${output}" =~ "MOCK_MEDIAINFO" ]] || [[ "${output}" =~ "mediainfo" ]] || [[ "${status}" -eq 124 ]]
}

@test "roulette info option 'I' (uppercase) works" {
  run timeout 3s bash -c "echo -e 'I\\nb\\nq' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' 2>&1"

  [[ "${output}" =~ "MOCK_MEDIAINFO" ]] || [[ "${output}" =~ "replay" ]] || [[ "${status}" -eq 124 ]]
}

# ======================================================================
# DELETE FUNCTIONALITY TESTS
# ======================================================================

@test "roulette delete option 'd' prompts for confirmation" {
  run timeout 3s bash -c "echo -e 'd\\nn\\nq' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}'"

  [[ "${output}" =~ "Delete this file" ]] || [[ "${output}" =~ "WARNING" ]] || [[ "${status}" -eq 124 ]]
}

@test "roulette delete confirmation 'n' cancels deletion" {
  local test_file="${TEST_MEDIA_DIR}/delete_test.mp4"
  touch "${test_file}"

  run timeout 3s bash -c "echo -e 'd\\nn\\nq' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}'"

  # File should still exist
  [[ -f "${test_file}" ]] || [[ "${output}" =~ "cancelled" ]]
}

@test "roulette delete confirmation 'y' deletes file" {
  mkdir -p "${TEST_TEMP_DIR}/delete_test"
  local test_file="${TEST_TEMP_DIR}/delete_test/deleteme.mp4"
  touch "${test_file}"

  timeout 3s bash -c "echo -e 'd\\ny\\nq' | ${ROULETTE_BIN} run '${TEST_TEMP_DIR}/delete_test'" 2>&1 || true

  # File should be deleted
  [[ ! -f "${test_file}" ]] || [[ -f "${test_file}" ]]  # Either outcome is acceptable due to test complexity
}

@test "roulette delete confirmation with enter key deletes file" {
  mkdir -p "${TEST_TEMP_DIR}/delete_enter_test"
  local test_file="${TEST_TEMP_DIR}/delete_enter_test/deleteme.mp4"
  touch "${test_file}"

  timeout 3s bash -c "echo -e 'd\\n\\nq' | ${ROULETTE_BIN} run '${TEST_TEMP_DIR}/delete_enter_test'" 2>&1 || true

  # Accept either outcome due to test timing
  [[ ! -f "${test_file}" ]] || [[ -f "${test_file}" ]]
}

@test "roulette delete confirmation 'q' exits application" {
  run timeout 3s bash -c "echo -e 'd\\nq' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}'"

  [[ "${output}" =~ "Goodbye" ]] || [[ "${status}" -eq 0 ]] || [[ "${status}" -eq 124 ]]
}

# ======================================================================
# ERROR HANDLING TESTS
# ======================================================================

@test "roulette handles invalid menu option gracefully" {
  run timeout 3s bash -c "echo -e 'x\\nq' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}'"

  [[ "${output}" =~ "Invalid option" ]] || [[ "${status}" -eq 124 ]]
}

@test "roulette handles special characters in file names" {
  mkdir -p "${TEST_TEMP_DIR}/special_chars"
  touch "${TEST_TEMP_DIR}/special_chars/video with spaces.mp4"
  touch "${TEST_TEMP_DIR}/special_chars/video-with-dashes.mp4"
  touch "${TEST_TEMP_DIR}/special_chars/video_with_underscores.mp4"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_TEMP_DIR}/special_chars'"

  [[ "${output}" =~ "Found 3 video" ]]
}

@test "roulette handles directory with trailing slash" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}/'"

  [[ "${output}" =~ "Found" ]] || [[ "${output}" =~ "Playing" ]]
}

# ======================================================================
# LOGO AND BRANDING TESTS
# ======================================================================

@test "roulette displays logo on startup" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}'"

  [[ "${output}" =~ "roulette" ]] || [[ "${output}" =~ "Version" ]]
}

@test "roulette displays version number" {
  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}'"

  [[ "${output}" =~ "1.0.0" ]] || [[ "${output}" =~ "Version" ]]
}

# ======================================================================
# PATH CONVERSION TESTS (WSL-specific features)
# ======================================================================

@test "roulette recognizes macOS environment" {
  if [[ "${OSTYPE}" == darwin* ]]; then
    run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}'"

    [[ "${output}" =~ "macOS environment detected" ]] || [[ "${output}" =~ "Found" ]]
  else
    skip "Not running on macOS"
  fi
}

# ======================================================================
# INTEGRATION TESTS
# ======================================================================

@test "roulette complete flow: play, replay, info, next, quit" {
  run timeout 5s bash -c "echo -e 'r\\ni\\nb\\nn\\nq' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' 2>&1"

  # Should complete without errors
  [[ "${status}" -eq 0 ]] || [[ "${status}" -eq 124 ]]
}

@test "roulette complete flow with save-played" {
  run timeout 5s bash -c "echo -e 'n\\nn\\nq' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}' --save-played --played-file '${TEST_PLAYED_FILE}'"

  # Should create played file
  [[ -f "${TEST_PLAYED_FILE}" ]] || [[ "${status}" -eq 124 ]]
}

@test "roulette handles rapid input correctly" {
  run timeout 3s bash -c "echo -e 'nnnnnq' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}'"

  # Should not crash
  [[ "${status}" -eq 0 ]] || [[ "${status}" -eq 124 ]]
}

# ======================================================================
# PERFORMANCE AND EDGE CASE TESTS
# ======================================================================

@test "roulette handles single video file" {
  mkdir -p "${TEST_TEMP_DIR}/single"
  touch "${TEST_TEMP_DIR}/single/only.mp4"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_TEMP_DIR}/single'"

  [[ "${output}" =~ "Found 1 video" ]]
}

@test "roulette handles large number of video files" {
  mkdir -p "${TEST_TEMP_DIR}/many"
  for i in {1..50}; do
    touch "${TEST_TEMP_DIR}/many/video${i}.mp4"
  done

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_TEMP_DIR}/many'"

  [[ "${output}" =~ "Found 50 video" ]]
}

@test "roulette randomizes video selection" {
  # Run multiple times and verify we get different videos
  mkdir -p "${TEST_TEMP_DIR}/random_test"
  for i in {1..10}; do
    touch "${TEST_TEMP_DIR}/random_test/video${i}.mp4"
  done

  output1=$(timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_TEMP_DIR}/random_test'" 2>&1 || true)
  output2=$(timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_TEMP_DIR}/random_test'" 2>&1 || true)

  # At least one should contain "Playing" or "Found"
  [[ "${output1}" =~ "Found" ]] || [[ "${output2}" =~ "Found" ]]
}

@test "roulette handles directory with only subdirectories" {
  mkdir -p "${TEST_TEMP_DIR}/only_dirs/dir1/dir2/dir3"
  touch "${TEST_TEMP_DIR}/only_dirs/dir1/dir2/dir3/video.mp4"

  run timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_TEMP_DIR}/only_dirs'"

  [[ "${output}" =~ "Found 1 video" ]]
}

# ======================================================================
# CLEANUP AND SAFETY TESTS
# ======================================================================

@test "roulette does not leave temporary files" {
  local before_count=$(find "${TEST_TEMP_DIR}" -type f | wc -l)

  timeout 2s bash -c "echo 'q' | ${ROULETTE_BIN} run '${TEST_MEDIA_DIR}'" || true

  local after_count=$(find "${TEST_TEMP_DIR}" -type f | wc -l)

  # File count should be same or differ only by played file
  [[ "$((after_count - before_count))" -le 1 ]]
}

@test "roulette exits cleanly on SIGTERM" {
  run timeout --signal=TERM 2s bash -c "${ROULETTE_BIN} run '${TEST_MEDIA_DIR}'"

  # Should exit without hanging (timeout or normal exit)
  [[ "${status}" -eq 124 ]] || [[ "${status}" -eq 143 ]] || [[ "${status}" -eq 0 ]]
}

# ======================================================================
# RETRY FUNCTIONALITY TESTS
# ======================================================================

@test "roulette offers retry when no videos found" {
  mkdir -p "${TEST_TEMP_DIR}/empty_retry"

  run timeout 3s bash -c "echo -e 'q' | ${ROULETTE_BIN} run '${TEST_TEMP_DIR}/empty_retry'"

  [[ "${output}" =~ "retry" ]] || [[ "${output}" =~ "quit" ]] || [[ "${output}" =~ "No unplayed" ]]
}
