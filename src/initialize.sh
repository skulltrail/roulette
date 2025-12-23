#!/usr/bin/env bash

GREEN='\033[1;32m'
NC='\033[0m'
# shellcheck disable=SC2034  # Used in command.sh
ICON="${GREEN}(::X::)${NC}"

VIDEO_EXTENSIONS=(
  mp4 avi mkv mov wmv flv webm m4v mpg mpeg mp4
)

MPV_PATH="/usr/local/bin/mpv"
MPV_PATH_ARM="/opt/homebrew/bin/mpv"
IS_WSL=false
IS_MACOS=false

print_logo() {
  cat <<'EOF'
    ----------------░░░░░░░-----------------
    ---.--'-'''.---░░]▄▄▄▄▄░░--`'''''-'-''''
    ---------------░░░╣▒░╠▌░░----'''''''''''
    ''---------;░░Q▄░▀╩▓╗▌╩╩Q▄▄░░----------'
    ''''''.'.-;░╠▀░░░░░░▓░░░░░░▀▒µ---'''''''
    ------'-»╔#░░▄╧--░░╚╠╩░░--@▄░╚▒░-'''''''
     ''-'---╓╝░░╙╚≤░-""░▓░░░░≤╛╚░∩╙╩░---'''
         '!░║░░----└▒░;░▓░,µ▒░----░]▌░-
         .-╣░░░░---░░│Φ░╙]▒│-----╓░"]▌-'
       ---░╣░"╠▒╚▀▀▀▀▀▒░▀░╚▀▀▀▀▀▒╚▒-]▌░-'
          .╝Q░,---.`,╗╩░φ░╚▄-''---░░░▌-
          `░║░----;@╚░':╣=-"▒╦░----]▌└'
           '-║▒-╙║░░---░▓░-"`░░φ▒-]▌└'
            '└╙░░-╙---»≤░≥----╙;]ƒ╛░'
               `╙▀╦▄Q--└░░'.╓Qƒ▀▒⌐
                 '└└└▀▀▀▀▀▀▀░└└''
EOF
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

build_mpv_args() {
  local args=()
  if [[ -n "${MPV_GEOMETRY}" ]]; then
    args+=("--geometry=${MPV_GEOMETRY}")
  fi
  if [[ -n "${MPV_VOLUME}" ]]; then
    args+=("--volume=${MPV_VOLUME}")
  fi
  echo "${args[@]}"
}

run_mpv() {
  local video_path="$1"
  local mpv_args
  mpv_args=$(build_mpv_args)

  if [[ -n "${ROULETTE_DEBUG}" || -n "${args['--debug']}" ]]; then
    echo -e "${GREEN}[DEBUG]${NC} ${MPV_PATH} ${mpv_args} \"${video_path}\""
  fi
  "${MPV_PATH}" "${mpv_args}" "${video_path}"
}

build_find_command() {
  local find_cmd="find \"${DIRECTORY_PATH}\" -type f \\\( "
  local first=true
  for ext in "${VIDEO_EXTENSIONS[@]}"; do
    if [[ "${first}" == true ]]; then
      find_cmd+="-iname \"*.${ext}\""
      first=false
    else
      find_cmd+=" -o -iname \"*.${ext}\""
    fi
  done
  find_cmd+=" \\\)"
  echo "${find_cmd}"
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

load_played_set() {
  PLAYED_SET_FILE="${args['--played-file']}"
  if [[ -z "${PLAYED_SET_FILE}" ]]; then
    PLAYED_SET_FILE="${HOME}/.roulette_played"
  fi
  declare -gA PLAYED_SET
  PLAYED_SET=()
  if [[ -f "${PLAYED_SET_FILE}" ]]; then
    while IFS= read -r line; do
      # shellcheck disable=SC2034  # PLAYED_SET used in command.sh
      [[ -n "${line}" ]] && PLAYED_SET["${line}"]=1
    done <"${PLAYED_SET_FILE}"
  fi
}

save_played() {
  local path="$1"
  [[ -z "${path}" ]] && return 0
  PLAYED_SET_FILE="${args['--played-file']}"
  if [[ -z "${PLAYED_SET_FILE}" ]]; then
    PLAYED_SET_FILE="${HOME}/.roulette_played"
  fi
  mkdir -p "$(dirname "${PLAYED_SET_FILE}")"
  printf "%s\n" "${path}" >>"${PLAYED_SET_FILE}"
}
