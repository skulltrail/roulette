#!/usr/bin/env bash
# shellcheck disable=SC2154  # GREEN, NC, ICON, YELLOW, RED, CYAN, DIM, version defined in initialize.sh
echo -e "${GREEN}"
print_logo
echo "   r o u l e t t e"
echo "   Version ${version}"
echo ""
echo -e "${NC}"

DIRECTORY_PATH=""
USER_PROVIDED_PATH=""

if [[ -n "${args[directory]}" ]]; then
  USER_PROVIDED_PATH="${args[directory]}"
  USER_PROVIDED_PATH="${USER_PROVIDED_PATH/#\~/${HOME}}"
  if [[ ! -d "${USER_PROVIDED_PATH}" ]]; then
    echo -e "${RED}ERROR:${NC} Directory not found: ${USER_PROVIDED_PATH}"
    exit 1
  fi
  DIRECTORY_PATH="${USER_PROVIDED_PATH}"
  echo "Using provided directory: ${DIRECTORY_PATH}"
fi

detect_macos
detect_wsl

if [[ -z "${USER_PROVIDED_PATH}" ]]; then
  detect_media_directory
fi

check_and_install_mpv

# Playlist file lives in the media directory
PLAYLIST_FILE="${DIRECTORY_PATH}/.roulette_playlist"

# Load or create playlist
if [[ -f "${PLAYLIST_FILE}" ]] && [[ -z "${args['--reset']}" ]]; then
  load_playlist "${PLAYLIST_FILE}"
  echo "Loaded playlist: ${#PLAYLIST[@]} videos remaining"
else
  if [[ -n "${args['--reset']}" ]]; then
    debug_log "Reset flag provided, rebuilding playlist"
  fi
  echo "Scanning directory: ${DIRECTORY_PATH}"
  PLAYLIST=()
  while IFS= read -r -d '' file; do
    PLAYLIST+=("${file}")
  done < <(list_videos)

  if [[ ${#PLAYLIST[@]} -eq 0 ]]; then
    echo "No video files found."
    exit 0
  fi

  save_playlist "${PLAYLIST_FILE}"
  echo "Found ${#PLAYLIST[@]} videos, saved playlist."
fi

open_random_video() {
  if [[ ${#PLAYLIST[@]} -eq 0 ]]; then
    echo "Playlist empty - all videos played!"
    echo "Use --reset to rebuild the playlist."
    return 1
  fi

  echo -e "${DIM}${#PLAYLIST[@]} videos remaining.${NC}"
  local random_index=$((RANDOM % ${#PLAYLIST[@]}))
  random_video="${PLAYLIST[${random_index}]}"
  debug_log "Selected index ${random_index} of ${#PLAYLIST[@]}: ${random_video}"

  # Verify file still exists
  if [[ ! -f "${random_video}" ]]; then
    debug_log "File not found, removing stale entry"
    echo "Video no longer exists, removing: ${random_video}"
    remove_from_playlist "${random_video}"
    save_playlist "${PLAYLIST_FILE}"
    return 2 # Signal to retry
  fi

  echo -e "${ICON} Playing: ${random_video}"

  local video_path
  video_path=$(convert_path_for_mpv "${random_video}")
  run_mpv "${video_path}"
}

while true; do
  open_random_video
  result=$?

  if [[ ${result} -eq 2 ]]; then
    # File not found, auto-retry
    continue
  elif [[ ${result} -eq 0 ]]; then
    # Track if video should be removed from playlist
    should_remove=false

    # Check if video was watched enough to auto-remove
    if is_video_watched_enough; then
      echo ""
      echo -e "${GREEN}Video watched (${LAST_PLAYBACK_PERCENT}%)${NC} - removed from playlist."
      should_remove=true
    else
      echo ""
      echo -e "${YELLOW}Video skipped (${LAST_PLAYBACK_PERCENT}%)${NC} - keeping in playlist."
    fi

    while true; do
      echo ""
      echo -e -n "[${CYAN}q${NC}]uit  [${RED}d${NC}]elete  [${DIM}i${NC}]nfo  [${DIM}r${NC}]eplay  [${GREEN}N${NC}]ext: "
      read -n 1 -r user_input
      echo
      debug_log "User input: '${user_input}'"

      case "${user_input}" in
        q | Q)
          debug_log "Action: quit"
          echo "Goodbye!"
          exit 0
          ;;
        r | R)
          debug_log "Action: replay"
          echo -e "${DIM}Replaying...${NC}"
          video_path=$(convert_path_for_mpv "${random_video}")
          run_mpv "${video_path}"
          continue
          ;;
        i | I)
          debug_log "Action: show info"
          mediainfo "${random_video}"
          while true; do
            echo -e -n "[${DIM}r${NC}]eplay  [${DIM}b${NC}]ack: "
            read -n 1 -r replay_input
            echo
            debug_log "Info submenu input: '${replay_input}'"
            case "${replay_input}" in
              r | R)
                debug_log "Action: replay from info"
                video_path=$(convert_path_for_mpv "${random_video}")
                run_mpv "${video_path}"
                ;;
              b | B | q | Q | $'\n' | "")
                debug_log "Action: back to main menu"
                break
                ;;
              *)
                echo -e "${YELLOW}Invalid option '${replay_input}'.${NC}"
                ;;
            esac
          done
          continue
          ;;
        d | D)
          debug_log "Action: delete prompt"
          echo ""
          echo -e "${RED}WARNING:${NC} This will permanently delete the file:"
          echo -e "${DIM}${random_video}${NC}"
          echo ""
          echo -e -n "Delete? [${RED}y${NC}/Enter=yes, ${DIM}n${NC}=no, ${CYAN}q${NC}=quit]: "
          read -n 1 -r confirmation
          echo
          debug_log "Delete confirmation: '${confirmation}'"
          case "${confirmation}" in
            y | Y | $'\n' | "")
              debug_log "Action: confirmed delete"
              if rm "${random_video}" 2>/dev/null; then
                echo -e "${GREEN}File deleted.${NC}"
                should_remove=true
              else
                echo -e "${RED}Failed to delete file.${NC} Check permissions."
              fi
              break
              ;;
            q | Q)
              debug_log "Action: quit from delete"
              echo "Goodbye!"
              exit 0
              ;;
            n | N | *)
              debug_log "Action: cancel delete"
              echo -e "${DIM}Cancelled.${NC}"
              continue
              ;;
          esac
          ;;
        n | N | ' ' | "")
          debug_log "Action: next video"
          break
          ;;
        *)
          echo -e "${YELLOW}Invalid option '${user_input}'.${NC}"
          continue
          ;;
      esac
    done

    # Remove from playlist if watched or deleted
    if [[ "${should_remove}" == true ]]; then
      remove_from_playlist "${random_video}"
      save_playlist "${PLAYLIST_FILE}"
    fi
  else
    echo ""
    echo -e -n "[${DIM}r${NC}]etry  [${CYAN}q${NC}]uit: "
    read -n 1 -r user_input
    echo
    case "${user_input}" in
      q | Q)
        echo "Goodbye!"
        exit 0
        ;;
      r | R)
        continue
        ;;
      *)
        echo -e "${YELLOW}Invalid option '${user_input}'.${NC}"
        ;;
    esac
  fi
done
