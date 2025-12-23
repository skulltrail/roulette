# shellcheck disable=SC2154  # GREEN, NC, ICON, version defined in initialize.sh
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
    echo "ERROR: Directory not found: ${USER_PROVIDED_PATH}"
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

if [[ -n "${args['--save-played']}" ]]; then
  load_played_set
fi

open_random_video() {
  if [[ ! -d "${DIRECTORY_PATH}" ]]; then
    echo "Directory not found: ${DIRECTORY_PATH}"
    return 1
  fi

  videos=()
  while IFS= read -r -d '' file; do
    if [[ -n "${args['--save-played']}" ]] && [[ -n "${PLAYED_SET["${file}"]}" ]]; then
      continue
    fi
    videos+=("${file}")
  done < <(list_videos)

  if [[ ${#videos[@]} -eq 0 ]]; then
    echo "No unplayed video files found in: ${DIRECTORY_PATH}"
    return 1
  fi

  echo "Found ${#videos[@]} video files."
  local random_index=$((RANDOM % ${#videos[@]}))
  random_video="${videos[${random_index}]}"
  echo -e "${ICON} Playing: ${random_video}"

  local video_path
  video_path=$(convert_path_for_mpv "${random_video}")
  run_mpv "${video_path}"

  if [[ -n "${args['--save-played']}" ]]; then
    save_played "${random_video}"
  fi
}

while true; do
  if open_random_video; then
    while true; do
      echo ""
      echo -n "[q]uit, [d]elete, [i]nfo, [r]eplay, [N]ext: "
      read -n 1 -r user_input
      echo

      case "${user_input}" in
        q | Q)
          echo "Goodbye!"
          exit 0
          ;;
        r | R)
          echo "Replaying video: ${random_video}"
          video_path=$(convert_path_for_mpv "${random_video}")
          run_mpv "${video_path}"
          continue
          ;;
        i | I)
          mediainfo "${random_video}"
          while true; do
            echo -n "[r]replay, [b]ack: "
            read -n 1 -r replay_input
            echo
            case "${replay_input}" in
              r | R)
                video_path=$(convert_path_for_mpv "${random_video}")
                run_mpv "${video_path}"
                ;;
              b | B | q | Q | $'\n' | "")
                break
                ;;
              *)
                echo "Invalid option '${replay_input}'. Try again..."
                ;;
            esac
          done
          continue
          ;;
        d | D)
          echo ""
          echo "WARNING: This will permanently delete the file:"
          echo "${random_video}"
          echo ""
          echo -n "Delete this file? [y/Enter=yes, n=no, q=quit]: "
          read -n 1 -r confirmation
          echo
          case "${confirmation}" in
            y | Y | $'\n' | "")
              if rm "${random_video}" 2>/dev/null; then
                echo "File deleted successfully."
              else
                echo "Failed to delete file. Check permissions."
              fi
              break
              ;;
            q | Q)
              echo "Goodbye!"
              exit 0
              ;;
            n | N | *)
              echo "File deletion cancelled."
              continue
              ;;
          esac
          ;;
        n | N | ' ' | "")
          break
          ;;
        *)
          echo "Invalid option '${user_input}'. Try again..."
          continue
          ;;
      esac
    done
  else
    echo ""
    echo -n "[r]etry, [q]uit: "
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
        echo "Invalid option '${user_input}'. Try again..."
        ;;
    esac
  fi
done
