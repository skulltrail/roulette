#!/usr/bin/env bash

# Colors (used in root_command.sh)
# shellcheck disable=SC2034
GREEN='\033[1;32m'
# shellcheck disable=SC2034
YELLOW='\033[1;33m'
# shellcheck disable=SC2034
RED='\033[1;31m'
# shellcheck disable=SC2034
CYAN='\033[1;36m'
# shellcheck disable=SC2034
DIM='\033[2m'
# shellcheck disable=SC2034
NC='\033[0m'
# shellcheck disable=SC2034
ICON="${GREEN}(::X::)${NC}"

# Debug logging function - prints verbose info when debug mode is enabled
debug_log() {
  if [[ -n "${ROULETTE_DEBUG}" || -n "${args['--debug']:-}" ]]; then
    echo -e "${DIM}[DEBUG]${NC} $*" >&2
  fi
}

VIDEO_EXTENSIONS=(
  mp4 avi mkv mov wmv flv webm m4v mpg mpeg mp4
)

MPV_PATH="/usr/local/bin/mpv"
MPV_PATH_ARM="/opt/homebrew/bin/mpv"
IS_WSL=false
IS_MACOS=false

print_logo() {
  printf '%s\n' "    ----------------░░░░░░░-----------------"
  printf '%s\n' "    ---.--'-'''.---░░]▄▄▄▄▄░░--\`'''''-'-''''"
  printf '%s\n' "    ---------------░░░╣▒░╠▌░░----'''''''''''"
  printf '%s\n' "    ''---------;░░Q▄░▀╩▓╗▌╩╩Q▄▄░░----------'"
  printf '%s\n' "    ''''''.'.-;░╠▀░░░░░░▓░░░░░░▀▒µ---'''''''"
  printf '%s\n' "    ------'-»╔#░░▄╧--░░╚╠╩░░--@▄░╚▒░-'''''''"
  printf '%s\n' "     ''-'---╓╝░░╙╚≤░-\"\"░▓░░░░≤╛╚░∩╙╩░---'''"
  printf '%s\n' "         '!░║░░----└▒░;░▓░,µ▒░----░]▌░-"
  printf '%s\n' "         .-╣░░░░---░░│Φ░╙]▒│-----╓░\"]▌-'"
  printf '%s\n' "       ---░╣░\"╠▒╚▀▀▀▀▀▒░▀░╚▀▀▀▀▀▒╚▒-]▌░-'"
  printf '%s\n' "          .╝Q░,---.'\`,╗╩░φ░╚▄-''---░░░▌-"
  printf '%s\n' "          \`░║░----;@╚░':╣=-\"▒╦░----]▌└'"
  printf '%s\n' "           '-║▒-╙║░░---░▓░-\"\`░░φ▒-]▌└'"
  printf '%s\n' "            '└╙░░-╙---»≤░≥----╙;]ƒ╛░'"
  printf '%s\n' "               \`╙▀╦▄Q--└░░'.╓Qƒ▀▒⌐"
  printf '%s\n' "                 '└└└▀▀▀▀▀▀▀░└└''"
}

detect_wsl() {
  if grep -qEi "(Microsoft|WSL)" /proc/version &>/dev/null; then
    IS_WSL=true
    echo "WSL environment detected."
  fi
}

detect_macos() {
  if [[ "${OSTYPE}" == darwin* ]]; then
    IS_MACOS=true
    echo "macOS environment detected."
  fi
}

detect_media_directory() {
  local potential_paths=()

  if [[ "${IS_MACOS}" == true ]]; then
    potential_paths=(
      "/Volumes/media/archive/video"
    )
  elif [[ "${IS_WSL}" == true ]]; then
    potential_paths=(
      "/mnt/media/archive/video"
      "/media/archive/video"
      "/mnt/m/media/archive/video"
    )
  else
    potential_paths=(
      "/media/archive/video"
      "/mnt/media/archive/video"
    )
  fi

  for path in "${potential_paths[@]}"; do
    if [[ -d "${path}" ]]; then
      DIRECTORY_PATH="${path}"
      echo "Found media directory: ${DIRECTORY_PATH}"
      return 0
    fi
  done

  if [[ "${IS_MACOS}" == true ]]; then
    DIRECTORY_PATH="/Volumes/media/archive/video"
  elif [[ "${IS_WSL}" == true ]]; then
    DIRECTORY_PATH="/mnt/media/archive/video"
  else
    DIRECTORY_PATH="/media/archive/video"
  fi

  echo "WARNING: Media directory not found. Using default: ${DIRECTORY_PATH}"
  return 1
}

check_and_install_mpv() {
  # Prefer PATH mpv if available (helps testing and custom installs)
  if command -v mpv &>/dev/null; then
    MPV_PATH="$(command -v mpv)"
    echo "mpv found in PATH: ${MPV_PATH}"
    return 0
  fi
  if [[ "${IS_WSL}" == true ]]; then
    local win_mpv_paths=(
      "/mnt/c/Program Files/mpv/mpv.exe"
      "/mnt/c/Program Files (x86)/mpv/mpv.exe"
      "/mnt/c/Users/${USER}/AppData/Local/Programs/mpv.net/mpvnet.exe"
      "$(command -v mpv.exe 2>/dev/null)"
    )

    for path in "${win_mpv_paths[@]}"; do
      if [[ -f "${path}" ]]; then
        MPV_PATH="${path}"
        echo "Found Windows MPV at: ${MPV_PATH}"
        return 0
      fi
    done

    echo "ERROR: mpv.exe not found on Windows side."
    echo "Please install mpv for Windows from https://mpv.io/installation/"
    echo "Or ensure mpv.exe is in your Windows PATH."
    exit 1
  fi

  if [[ -f "${MPV_PATH}" ]] || [[ -f "${MPV_PATH_ARM}" ]]; then
    echo "mpv is already installed."
    if [[ -f "${MPV_PATH_ARM}" ]]; then
      MPV_PATH="${MPV_PATH_ARM}"
    fi
  else
    echo "mpv is not installed. Installing using Homebrew..."
    if ! command -v brew &>/dev/null; then
      echo "Homebrew is not installed. Please install Homebrew first:"
      echo "Visit https://brew.sh for installation instructions"
      exit 1
    fi
    if brew install mpv; then
      echo "mpv installed successfully."
      if [[ -f "${MPV_PATH_ARM}" ]]; then
        MPV_PATH="${MPV_PATH_ARM}"
      fi
    else
      echo "Failed to install mpv using Homebrew. Please install it manually."
      exit 1
    fi
  fi
}

convert_path_for_mpv() {
  local path="$1"
  if [[ "${IS_WSL}" == true ]]; then
    wslpath -w "${path}"
  else
    echo "${path}"
  fi
}

# Playback progress tracking
LAST_PLAYBACK_PERCENT=0

# Threshold for considering a video "watched" (percentage)
WATCHED_THRESHOLD_PERCENT=10

build_mpv_args() {
  local mpv_opts=()
  debug_log "Building mpv args: MPV_GEOMETRY='${MPV_GEOMETRY}' MPV_VOLUME='${MPV_VOLUME}'"
  if [[ -n "${MPV_GEOMETRY}" ]]; then
    mpv_opts+=("--geometry=${MPV_GEOMETRY}")
  fi
  if [[ -n "${MPV_VOLUME}" ]]; then
    mpv_opts+=("--volume=${MPV_VOLUME}")
  fi
  echo "${mpv_opts[@]}"
}

run_mpv() {
  local video_path="$1"
  local mpv_args
  mpv_args=$(build_mpv_args)

  debug_log "Executing: ${MPV_PATH} ${mpv_args} \"${video_path}\""

  # Reset playback tracking
  LAST_PLAYBACK_PERCENT=0

  # Run mpv and capture stderr to parse progress
  # mpv outputs status line like: AV: 00:00:02 / 00:39:45 (0%) A-V: -0.000
  local mpv_output
  # shellcheck disable=SC2086  # mpv_args intentionally unquoted - empty string should expand to nothing
  mpv_output=$("${MPV_PATH}" ${mpv_args} "${video_path}" 2>&1)
  local exit_code=$?

  # Parse the last AV line for progress percentage
  local percent
  percent=$(echo "${mpv_output}" | grep -o '([0-9]*%)' | tail -1 | tr -d '()%')
  if [[ -n "${percent}" ]]; then
    LAST_PLAYBACK_PERCENT="${percent}"
  fi

  debug_log "mpv exited with code ${exit_code}, playback: ${LAST_PLAYBACK_PERCENT}%"
  return ${exit_code}
}

is_video_watched_enough() {
  [[ ${LAST_PLAYBACK_PERCENT} -ge ${WATCHED_THRESHOLD_PERCENT} ]]
}

list_videos() {
  local find_args=(find "${DIRECTORY_PATH}" -type f '(')
  local i
  for ((i = 0; i < ${#VIDEO_EXTENSIONS[@]}; i++)); do
    local ext="${VIDEO_EXTENSIONS[${i}]}"
    find_args+=(-iname "*.${ext}")
    if ((i < ${#VIDEO_EXTENSIONS[@]} - 1)); then
      find_args+=(-o)
    fi
  done
  find_args+=(')')
  find_args+=(-print0)
  "${find_args[@]}"
}

# Playlist management functions
PLAYLIST=()

load_playlist() {
  local playlist_file="$1"
  debug_log "Loading playlist from: ${playlist_file}"
  PLAYLIST=()
  [[ ! -f "${playlist_file}" ]] && return 1
  while IFS= read -r line; do
    [[ -n "${line}" ]] && PLAYLIST+=("${line}")
  done <"${playlist_file}"
  debug_log "Loaded ${#PLAYLIST[@]} entries from playlist"
  return 0
}

save_playlist() {
  local playlist_file="$1"
  debug_log "Saving playlist to: ${playlist_file} (${#PLAYLIST[@]} entries)"
  mkdir -p "$(dirname "${playlist_file}")"
  printf '%s\n' "${PLAYLIST[@]}" >"${playlist_file}"
}

remove_from_playlist() {
  local video_to_remove="$1"
  debug_log "Removing from playlist: ${video_to_remove}"
  local new_playlist=()
  for v in "${PLAYLIST[@]}"; do
    [[ "${v}" != "${video_to_remove}" ]] && new_playlist+=("${v}")
  done
  PLAYLIST=("${new_playlist[@]}")
  debug_log "Playlist now has ${#PLAYLIST[@]} entries"
}
