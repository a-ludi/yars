#!/bin/bash -x
# This script makes incremental or full backups of a given folder using rsync.
#     Copyright (C) 2013  Arne Ludwig <ludwig.arne@gmail.com>
#
#     This program is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 3 of the License, or
#     (at your option) any later version.
#
#     This program is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with this program.  If not, see <http://www.gnu.org/licenses/>.

# This is the folder to make a backup of. If you want to backup its contents
# only you have to precede it with a blackslash ('/'); otherwise the folder
# itself will be copied.
: ${SOURCE:=''}

# This is the destination folder. It can be any local or remote folder. Make
# sure it exists and you have write permissions.
# For each backup a subfolder named 'YYYY-mm-dd-MM-HH-SS' will be created. If
# the creation fails the script will exit with a status of 2.
: ${DESTINATION:=''}

# Exclude file patterns from the backup (see --exclude option from rsync). You
# may specify multiple patterns separated by colons (':').
: ${EXCLUDE:=''}

# This provides a way to control rsync. This OVERRIDES the default options (see
# RSYNC_OPTIONS below).
: ${RSYNC_OPTIONS:=''}

# If a log file is given a new line for each run will be generated; unless the
# call results in the help or version being shown.
: ${LOG:=''}


# The following options control the magnitude of the overall backup. Magnitude
# relates to number, age or file size. All deletion takes place AFTER the
# current backup unless the --delete-only options is present.

# If you set this option to a positive integer only that much backups will be
# kept, ie every odd backup will be deleted beginning with the oldest.
: ${KEEP_NUM:=0}

# TODO make a adaptive history, eg:
#     - the last 60 minutes
#     - the last 24 hour
#     - the last 30 days
#     - the last 12 month
#     - the last 2 years

# If you set this option to a to some abitrary date only backups newer than that
# date will be kept; if the date lies in the future nothing is deleted and a
# warning is issued. This options respects the KEEP_NUM option and preserves at
# least KEEP_NUM backups.
#
# The date string must be understood by 'date --date=STRING', eg '3 months ago'.
# Refer to `man date` and `info coreutils 'date input formats'` for details.
: ${KEEP_AFTER:=''}

# TODO KEEP_SIZE not implemented
# If you set this option to a positive file size value the overall size of the
# backups is kept under that size, ie AFTER creation of the actual backup the
# oldest backup gets deleted until the size drops below that value. Valid values
# include:
#   3M      # equals 3 MiB = 3 * 2^20 Bytes
#   4K      # equals 4 KiB = 4 * 2^10 Bytes
#   512     # equals 512 KiB = 512 * 2^10 Bytes
#   1.2G    # equals 1.2 GiB = 1.2 * 2^30 Bytes
#
# Refer to the documentation of TODO for details.
: ${KEEP_SIZE:=0}


# EDIT ANYTHING FROM HERE ON YOUR OWN RISK.
#
# --- SCRIPT BEGIN -------------------------------------------------------------

VERSION="v0.1.7a 2013-09-02"

# Matches a timestamp as produced by the function with the same name and an
# optional trailing backslash ('/')
TIMESTAMP_REGEX="^[0-9]{4}(-[0-5][0-9]){5}\/?$"

# TODO fetch paths from command line as last two params
# TODO fetch EXCLUDE, LOG, KEEP_* from command line
function print_help {
  (
    echo "USAGE $(basename "$0") [-f|--full|-d|--delete-only] [-s|--suppress-clutter] [-h|--help] [-v|--version]"
    echo "  -f, --full              Run a full backup (instead of incremental)"
    echo "  -d, --delete-only       Just delete backups to meet magnitude requirements"
    echo "  -s, --suppress-clutter  Delete backup if no changes were detected"
    echo "  -v, --version           Display version number, copyright info and exit"
    echo "  -h, --help, --usage     Display this help and exit"
    echo
    echo "Configure this script to match your own needs by editing this file or by setting the appropriate environment variables"
  ) 1>&2
}

function print_version {
  (
    echo "$(basename "$0") ${VERSION}"
    echo
    echo "Copyright (C) 2013  Arne Ludwig <ludwig.arne@gmail.com>"
    echo "This program comes with ABSOLUTELY NO WARRANTY."
    echo "This is free software, and you are welcome to redistribute it"
    echo "under certain conditions; for details look into the source code."
  ) 1>&2
}

function report_unkown_option {
  echo "error: unkown option '$1'" 1>&2
}

function log {
  if [[ -n ${LOG} ]]; then
    echo "$(date +'%F %T') $(whoami)@$(hostname) $0[$$] $1" >> "${LOG}"
  fi
}

function timestamp {
  date +%Y-%m-%d-%H-%M-%S --date="${1:-now}"
}

function is_before {
  if [[ "$1" =~ ${TIMESTAMP_REGEX} ]]; then
    # remove hyphens and backslashes
    __is_before_DATE1=${1//[\/-]/}
  else
    __is_before_DATE1=$(date +%Y%m%d%H%M%S --date="${1:-now}")
  fi

  if [[ "$2" =~ ${TIMESTAMP_REGEX} ]]; then
    # remove hyphens and backslashes
    __is_before_DATE2=${2//[\/-]/}
  else
    __is_before_DATE2=$(date +%Y%m%d%H%M%S --date="${2:-now}")
  fi

  (( __is_before_DATE1 < __is_before_DATE2 ))
}


# Command line processing
for ARG in "$@"; do
  case ${ARG} in
    -f|--full)
      REQUIRE_FULL=1
      ;;
    -d|--delete-only)
      DELETE_ONLY=1
      ;;
    -s|--suppress-clutter)
      SUPPRESS_CLUTTER=1
      ;;
    -v|--version)
      SHOW_VERSION=1
      ;;
    -h|--help)
      HELP=1
      ;;
    *)
      report_unkown_option "${ARG}"
      OPTIONS_ERROR=1
      ;;
  esac
done

if (( REQUIRE_FULL && DELETE_ONLY )); then
  echo "error: --full and --delete-only are mutual exclusive" 1>&2
  OPTIONS_ERROR=1
fi

# If necessary print usage or version and exit
if (( HELP || OPTIONS_ERROR )); then
  print_help
  exit ${OPTIONS_ERROR}
elif (( SHOW_VERSION )); then
  print_version
  exit 0
fi

if (( ! DELETE_ONLY )); then
  # Assert DESTINATION exists
  mkdir -p "${DESTINATION}"

  # Lists subdirectories of DESTINATION in descending order and trailing '/' for
  # directories. This format is then parsed by grep (see above).
  PREVIOUS_BACKUP=$(ls -1Fr "${DESTINATION}" | grep -m1 -E "${TIMESTAMP_REGEX}")
  HAVE_PREVIOUS_BACKUP=$(( $? == 0 ))

  PREVIOUS_BACKUP="${DESTINATION}/${PREVIOUS_BACKUP}"
  CURRENT_BACKUP="${DESTINATION}/$(timestamp)"

  LOCAL_RSYNC_OPTIONS='--no-verbose --itemize-changes'

  # Include the patterns from EXCLUDE
  OLD_IFS="${IFS}"
  IFS=":"
  for EXLUDE_PATH in $EXCLUDE; do
    LOCAL_RSYNC_OPTIONS+=" --exclude ${EXLUDE_PATH}"
  done
  IFS="${OLD_IFS}"

  # Default options (see 'man rsync' for details):
  #   -a                 archive mode; equals -rlptgoD (no -H,-A,-X)
  #   -h                 output numbers in a human-readable format
  #   --delete           delete extraneous files from dest dirs
  : ${RSYNC_OPTIONS:='-ah --delete'}

  # Make incremental backup by default ...
  # but only if we have a previous backup and no full backup is required
  if (( HAVE_PREVIOUS_BACKUP && ! REQUIRE_FULL )); then
    LOCAL_RSYNC_OPTIONS+=" --link-dest=${PREVIOUS_BACKUP}"
  fi

  # Dry run rsync to make check for differences ...
  if (( SUPPRESS_CLUTTER )); then
    CHANGES=$(rsync ${LOCAL_RSYNC_OPTIONS} --dry-run ${RSYNC_OPTIONS} ${SOURCE} ${CURRENT_BACKUP})
  fi

  # Check if there were changes
  if [[ -n ${CHANGES} ]] || (( ! SUPPRESS_CLUTTER )); then
    # Finally, run rsync to make the backup ...
    rsync ${LOCAL_RSYNC_OPTIONS} ${RSYNC_OPTIONS} "${SOURCE}" "${CURRENT_BACKUP}"

    if (( $? == 0 )); then
      log 'backup done'
    else
      log 'backup failed'
    fi
  else
    log 'everything in sync; backup done'
    echo "Nothing done -- everything's in sync. :)" 1>&2
  fi
fi


# Now, let's delete old backups if desired!

# Count the present backups (see PREVIOUS_BACKUP for details)
NUM_BACKUPS=$(ls -1F "${DESTINATION}" | grep -cE "${TIMESTAMP_REGEX}")
if (( KEEP_NUM > 0 )); then
  # Delete the oldest backup until the count drops below NUM_BACKUPS
  until (( NUM_BACKUPS <= KEEP_NUM )); do
    # Get the oldest backup's name (see PREVIOUS_BACKUP for details)
    OLDEST_BACKUP=$(ls -1F "${DESTINATION}" | grep -m1 -E "${TIMESTAMP_REGEX}")
    OLDEST_BACKUP="${DESTINATION}/${OLDEST_BACKUP}"

    rm -rf "${OLDEST_BACKUP}"
    NUM_BACKUPS=$(( NUM_BACKUPS - 1 ))
  done
fi

if [[ -n ${KEEP_AFTER} ]]; then
  if is_before "${KEEP_AFTER}" 'now'; then
    for BACKUP in $(ls -1F "${DESTINATION}" | grep -E "${TIMESTAMP_REGEX}"); do
      if is_before "${BACKUP}" "${KEEP_AFTER}"; then
        if [[ -n ${KEEP_NUM} ]] && (( NUM_BACKUPS > KEEP_NUM )); then
          rm -rf "${DESTINATION}/${BACKUP}"
          NUM_BACKUPS=$(( NUM_BACKUPS - 1 ))
        elif [[ -z ${KEEP_NUM} ]]; then
          rm -rf "${DESTINATION}/${BACKUP}"
        fi
      fi
    done
  else
    echo 'warning: KEEP_AFTER lies in the future; doing nothing' >&2
    log 'warning: KEEP_AFTER lies in the future; doing nothing'
  fi
fi