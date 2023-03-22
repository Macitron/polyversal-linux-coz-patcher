#!/usr/bin/env bash

# Usage syntax: `./polyversal.sh GAME_SHORTNAME PATCH_FOLDER_PATH`
function print_usage() {
  cat << EOF >&2
Usage:
 GUI:
  $0
 CLI:
  $0 <game_shortname> <patch_folder_path>

Game shortnames:
  'chn', 'sg', 'rne', 'cc', 'sg0', 'rnd'

EOF
}

# Want `./polyversal.sh chn` and `./polyversal.sh CHN` to work the same
function tolower() {
  printf '%s' "$*" | tr '[:upper:]' '[:lower:]'
}

# Returns whether the argument is a relative path or not, based solely on
# whether the path starts with a '/'.
function is_relpath() {
  printf '%s' "$1" | grep -qE '^/' - && return 1 || return 0
}

# `command -v COMMAND` prints information about COMMAND, but importantly has
# exit status 0 if the command exists and 1 if it does not. This true/false
# value is what we use in this script to determine whether a command is
# installed and available on the system.
function is_cmd() {
  command -v "$1" > /dev/null
}

# I like colors. `tput` seems fairly portable, so it's used here to dictate
# logging capabilities. Only log with colors if `tput` is available, stderr
# outputs to a terminal, and it supports 8 or more colors.
txt_normal=''
txt_yellow=''
txt_red=''
if is_cmd tput && test -t 2 && [[ "$(tput colors)" -ge 8 ]]; then
  txt_normal="$(tput sgr0)"
  txt_yellow="$(tput setaf 3)"
  txt_red="$(tput setaf 1)"
fi

# log_msg <info|warn|err> <message>
function log_msg() {
  case $(tolower "$1") in
    'warn' | 'w')
      sevpfx="${txt_yellow}$0: WARN:"
      ;;
    'error' | 'err' | 'e')
      sevpfx="${txt_red}$0: ERR:"
      ;;
    'info' | 'i')
      sevpfx="$0: INFO:"
      ;;
    *)
      # Well I don't necessarily want the program to die immediately, so just do
      # whatever ig
      sevpfx="$0: $1:"
      ;;
  esac
  printf '%s %s%s\n' "$sevpfx" "${*:2}" "${txt_normal}" >&2
}
function log_info() { log_msg info "$*"; }
function log_warn() { log_msg warn "$*"; }
function log_err() { log_msg err "$*"; }

# Handle non-zero exit statuses from Zenity.
# **Must be called immediately after zenity command.**
# Single optional argument is the message to be displayed in the case that the
# user closes the window.
function handle_zenity() {
  zen_ret=$?
  closedmsg="$*"
  [[ ! "$closedmsg" ]] && closedmsg="You must select an option."
  case $zen_ret in
    1)
      log_err "$closedmsg"
      exit 1
      ;;
    5)
      log_err "The input dialogue timed out."
      exit 1
      ;;
    -1)
      log_err "An unexpected error occurred using Zenity."
      exit 1
      ;;
  esac
}


arg_game=
arg_patchdir=
if [[ $# -eq 0 ]]; then
  # Assume GUI mode
  if ! is_cmd zenity; then
    log_err "Zenity is required to run this script in GUI mode. Please make sure you have it installed, then try again."
    # TODO (maybe): implement with Kdialog. probably not worth until someone files an issue/PR
    print_usage
    exit 1
  fi

  arg_game=$(zenity --list --radiolist --title "Choose Which Game to Patch" \
      --height 400 --width 600            \
      --column "Select" --column "Title"  \
      TRUE  'Chaos;Head NoAH'             \
      FALSE 'Steins;Gate'                 \
      FALSE 'Robotics;Notes Elite'        \
      FALSE 'Chaos;Child'                 \
      FALSE 'Steins;Gate 0'               \
      FALSE 'Robotics;Notes DaSH')
  handle_zenity "You must select which game to patch for the script to work."

  arg_patchdir=$(zenity --file-selection --title "Choose Patch Directory for $arg_game" \
      --directory --filename "$HOME/Downloads")
  handle_zenity "You must select the directory containing the patch for the script to work."
elif [[ $# -eq 2 ]]; then
  arg_game="$1"
  arg_patchdir="$2"
else
  printf '%s\n' 'Invalid syntax' >&2
  print_usage
  exit 1
fi


# Get the app ID and what the installer exe should be, based on the shortname.
# IDs are available in the README.
# CoZ's naming conventions are beautifully consistent, pls never change them
appid=
patch_exe=
gamename=
has_steamgrid=
needs_sgfix=
case $(tolower "$arg_game") in
  'chn' | 'ch' | 'chaos'[\;\ ]'head noah')
    appid=1961950
    patch_exe='CHNSteamPatch-Installer.exe'
    gamename="Chaos;Head NoAH"
    has_steamgrid=1
    ;;
  'sg' | 'steins'[\;\ ]'gate')
    appid=412830
    patch_exe='SGPatch-Installer.exe'
    gamename="Steins;Gate"
    needs_sgfix=1
    ;;
  'rne' | 'rn' | 'robotics'[\;\ ]'notes elite')
    appid=1111380
    patch_exe='RNEPatch-Installer.exe'
    gamename="Robotics;Notes Elite"
    ;;
  'cc' | 'chaos'[\;\ ]'child')
    appid=970570
    patch_exe='CCPatch-Installer.exe'
    gamename="Chaos;Child"
    ;;
  'sg0' | '0' | 'steins'[\;\ ]'gate 0')
    appid=825630
    patch_exe='SG0Patch-Installer.exe'
    gamename="Steins;Gate 0"
    ;;
  'rnd' | 'dash' | 'robotics'[\;\ ]'notes dash')
    appid=1111390
    patch_exe='RNDPatch-Installer.exe'
    gamename="Robotics;Notes DaSH"
    ;;
  *)
    log_err "shortname '$arg_game' is invalid"
    print_usage
    exit 1
    ;;
esac

log_info "patching $gamename using app ID $appid, expecting patch EXE name '$patch_exe' ..."
[[ $has_steamgrid ]] && log_info "using custom SteamGrid images ..."


# Make sure the patch directory ($arg_patchdir) is valid.
# "Valid" here means:
# (1) it exists, and
# (2) it contains the expected patch EXE file to execute
if [[ ! -d "$arg_patchdir" ]]; then
  log_err "directory '$arg_patchdir' does not exist"
  exit 1
fi

if [[ ! -f "$arg_patchdir/$patch_exe" ]]; then
  log_err "expected patch EXE '$patch_exe' does not exist within directory '$arg_patchdir'"
  exit 1
fi

# Since we're running `cd` from within protontricks, we need to get the absolute
# path to the patch directory. Relative paths won't work for this since the
# shell invoked by `protontricks -c` sets its CWD to the game's directory.
# Prefer `realpath` to do the job, but if it's not available then get it by
# concatenating the user's CWD and the relative path. Simple testing shows that
# this hack does not work on Flatpak Protontricks.
patch_dir="$arg_patchdir"
if is_relpath "$arg_patchdir"; then
  if is_cmd realpath; then
    patch_dir=$(realpath "$arg_patchdir")
  else
    log_warn "'realpath' not available as a command."
    log_warn "attempting to manually set absolute path; this might cause issues."
    log_warn "if you get an error citing a non-existent file or directory, try supplying the path to the patch directory as absolute or homedir-relative."
    patch_dir="$(pwd)/$arg_patchdir"
  fi
fi


# Detect whether the machine is a Steam Deck.
is_deck=
if grep -qE '^VERSION_CODENAME=holo' /etc/os-release; then
  is_deck=1
  log_info "detected Steam Deck environment ..."
fi

# We need either system Protontricks or Flatpak Protontricks to work the magic.
# Prefer system Protontricks if it exists since there's less to set up.
protontricks_cmd='protontricks'
fp_protontricks='com.github.Matoking.protontricks'
if is_cmd protontricks; then
  log_info "detected system install of protontricks ..."
else
  log_info "system install of protontricks not found. proceeding with flatpak ..."
  if ! is_cmd flatpak; then
    log_err "neither flatpak nor system protontricks was detected."
    log_err "please install one of the two and then try again."
    exit 1
  fi
  if ! flatpak list | grep -q "$fp_protontricks" -; then
    log_info "protontricks is not installed on flatpak. attempting installation ..."
    if ! flatpak install $fp_protontricks; then
      log_err "an error occurred while installing flatpak protontricks."
      exit 1
    fi
    log_info "flatpak protontricks installed successfully"
  fi
  protontricks_cmd="flatpak run $fp_protontricks"

  # Flatpak Protontricks has to be given access to the game's Steam folder to
  # make changes. On Deck this is (hopefully) as easy as giving it access to all
  # of its mounts and partitions; on PC, this could involve some tricky parsing
  # of VDF files to give it access to different library folders.
  [[ $is_deck ]] && flatpak override --user --filesystem=/run/media/ $fp_protontricks

  # TODO: parse VDF files to give it access to different library folders. For
  # now, FP Protontricks gives the user a prompt telling it which folder to give
  # access to anyway, so it's not too big of an issue as long as the user can
  # (a) read, and (b) copy and paste a single command.
fi


# Patch the game
log_info "patching $gamename ..."
compat_mts=
[[ $is_deck ]] && compat_mts="STEAM_COMPAT_MOUNTS=/run/media/"
if ! $protontricks_cmd -c "cd \"$patch_dir\" && $compat_mts wine $patch_exe" $appid
then
  log_warn "patch installation exited with nonzero status."
  log_warn "consult the output for errors."
else
  log_info "patch installation finished, no errors signaled."
fi
stty sane  # band-aid for newline wonkiness that wine sometimes creates

# CHN CoZ patch includes custom SteamGrid images, but since the patch is built for
# Windows, the placement of those files ends up happening within the Wine prefix 
# instead of the system-level Steam install. The following code will detect the 
# STEAMGRID folder within the patch directory, and if it exists, copy any *.png 
# files at its root to Steam userdata/<user_id>/config/grid within a default Steam 
# path install ($HOME/.local/share/Steam)
#
# TODO: Add support for flatpak Steam installs.
if [[ $has_steamgrid ]]; then
  log_info "copying custom SteamGrid images ..."
  for grid_dir in "$HOME/.local/share/Steam/userdata/"*/config/grid; do
    cp "$patch_dir/STEAMGRID/"*.png "$grid_dir/"
  done
  log_info "SteamGrid images copied."
fi

# S;G launches the default launcher via `Launcher.exe` for some reason instead
# of the patched `LauncherC0.exe`.
# Fix by symlinking Launcher to LauncherC0.
if [[ $needs_sgfix ]]; then
  log_info "fixing STEINS;GATE launcher issue ..."

  # Return info about symlinking process via exit code.
  # 0 means everything was fine and dandy,
  # 1 means Launcher.exe already points to LauncherC0.exe,
  # 2 means one or both of the files doesn't exist.
  sg_shcmd=$(cat << EOF
if [[ ! ( -f Launcher.exe && -f LauncherC0.exe ) ]]; then
  printf '%s\n\n%s\n' "Files in \$(pwd):" "\$(ls)"
  exit 2
fi
[[ \$(readlink Launcher.exe) == LauncherC0.exe ]] && exit 1
mv Launcher.exe Launcher.exe_bkp
ln -s LauncherC0.exe Launcher.exe
EOF
)
  $protontricks_cmd -c "$sg_shcmd" $appid
  cmdret=$?
  case $cmdret in
    0)
      log_info "launcher symlinked successfully."
      ;;
    1)
      log_warn "Launcher.exe was already symlinked to LauncherC0.exe."
      log_warn "have you already run this script?"
      ;;
    2)
      log_err "one or both of Launcher.exe or LauncherC0.exe did not exist."
      log_err "check output for contents of the game directory."
      log_err "was the patch not installed correctly?"
      ;;
    *)
      log_warn "symlink script exited with unexpected status code $cmdret."
      log_warn "consult the output for clues."
      ;;
  esac
fi
