#!/usr/bin/env bash

# Author: https://github.com/jemdiggity

#Script to sync lightroom database and image files to another filesystem and AWS S3.

set -e

SUCCESS=0
FAILURE=1

VERBOSE=0

CLEAN_DATE=""

IGNORED_FILES="*.DS_Store"

_arg_backups=off
_arg_previews=on

function die ()
{
  local _ret=$2
  test -n "$_ret" || _ret=1
  test "$_PRINT_HELP" = yes && print_help >&2
  echo "$1" >&2
  exit ${_ret}
}

function print_help ()
{
  printf 'Usage: %s command [args] <src> <dst>\n' "$0"
  printf "\t%s\n" "<command>: 'init' or 'push' or 'pull'"
  printf "\t%s\n" "<src>: source"
  printf "\t%s\n" "<dst>: destinatinon"
  printf "\t%s\n" "-h,--help: Prints help"
}

function isdigit ()    # Tests whether *entire string* is numerical.
{             # In other words, tests for integer variable.
[ $# -eq 1 ] || return $FAILURE

case $1 in
  *[!0-9]*|"") return $FAILURE;;
*) return $SUCCESS;;
esac
}

function date_check ()
{
  #should be in format yyyy-mm-dd, yyyy-mm, yyyy, or empty
  CLEAN_DATE=""
  if [ "$@" == "" ]; then
    return $SUCCESS
  fi
  
  year=`echo $@       | awk -F'-' '{print $1}'`
  month=`echo $@      | awk -F'-' '{print $2}'`
  dayOfMonth=`echo $@ | awk -F'-' '{print $3}'`

  isdigit "$year" || return $FAILURE
  
  CLEAN_DATE="$year"

  if [ "$month" != "" ]; then
    isdigit "$month" || return $FAILURE
    
    CLEAN_DATE="$year-$month"
  fi
  
  if [ "$dayOfMonth" != "" ]; then
    isdigit "$dayOfMonth" || return $FAILURE
    
    CLEAN_DATE="$year-$month-$dayOfMonth"
  fi    
  
  return $SUCCESS
}

function check_options {
  if [[ "$_src" == "" ]]; then
    echo "_src empty"
    return $FAILURE
  fi
  if [[ "$_dst" == "" ]]; then
    echo "_dst empty"
    return $FAILURE
  fi

  #Remove trailing slash for non-weird behaviour with sync program
  _src=${_src%/}
  _dst=${_dst%/}
  return $SUCCESS
}

function check_options_restore {
  if [[ "$_bucket_name" == "" ]]; then
    echo "_bucket_name empty"
    return $FAILURE
  fi
}

function init {
  # Copy Lightroom database into local dir.
  check_options || return $FAILURE

  if [[ "$_src" == "s3://"* ]]; then
    echo "If you see errors related to glacier storage, you may need to manually restore items via AWS console."
    NO_BACKUPS=""
    NO_PREVIEWS=""
    if [[ $_arg_backups == "off" ]]; then
      echo "Not syncing backup files for faster initialization."
      NO_BACKUPS="*Lightroom/Backups/*"
    fi
    if [[ $_arg_previews == "off" ]]; then
     echo "Not syncing preview files for faster initialization."
     NO_PREVIEWS="*Lightroom/Lightroom*Previews*/*"
    fi
    aws s3 sync --force-glacier-transfer --exclude "*" --include "Lightroom/*" --exclude "${NO_BACKUPS}" --exclude "${NO_PREVIEWS}" --include "*Lightroom/Lightroom*Previews*/*.db" --exclude "$IGNORED_FILES" "$_src" "$_dst"
  else
    cp -av "${_src}/Lightroom" "$_dst"
  fi
}

function push() {
  check_options || return $FAILURE

  if [[ "$_src" == "s3://"* ]] || [[ "$_dst" == "s3://"* ]]; then
    echo "Pushing Lightroom data to $_dst"
    aws s3 sync --exclude "*" --include "*Lightroom/*" --exclude "*Lightroom/Backups/*" --exclude "$IGNORED_FILES" "$_src" "$_dst"
    echo "Pushing media to $_dst"
    aws s3 sync --size-only --exclude "*" --include "19??/*" --include "20??/*" --exclude "$IGNORED_FILES" "$_src" "$_dst"
  else
    echo "Pushing to $_dst"
    rsync -avz "$_src" "$_dst"
  fi
}

function do_restore() {
  #pipe into shell so failures are ignored
  #for example, if the object is already being retrieved
  aws s3api list-objects-v2 \
    --bucket $_bucket_name \
    --query "Contents[?StorageClass=='GLACIER']" \
    --output text --prefix ${prefix} \
    | awk -F $'\t' -v q="'" '{print q$2q}' \
    | tr '\n' '\0' \
    | xargs -L 1 -0 echo aws s3api restore-object --restore-request Days=7 --bucket "$_bucket_name" --key \
    | sh
}

function restore() {
  #restore from glacier
  check_options_restore || return $FAILURE

  date=$_arg_date

  date_check "$date" || return $FAILURE

  year=`echo $CLEAN_DATE | awk -F'-' '{print $1}'`
  month=`echo $CLEAN_DATE | awk -F'-' '{print $2}'`
  dayOfMonth=`echo $CLEAN_DATE | awk -F'-' '{print $3}'`

   if [ "$dayOfMonth" == "" ]; then
    if [ "$month" == "" ]; then
      if [ "$year" == "" ]; then
        echo "Include the date to restore"
        die
      else
        echo "Restoring whole year: $year"
        prefix="$year"
        do_restore
      fi
    else
      echo "Restoring whole month: $year-$month"
      prefix="$year/$year-$month"
      do_restore
    fi
  else
    echo "Restoring date: $year-$month-$dayOfMonth"
    prefix="$year/$year-$month-$dayOfMonth"
    do_restore
  fi
}

function pull() {
  check_options || return $FAILURE
  
  date=$_arg_date
  
  date_check "$date" || return $FAILURE
  
  year=`echo $CLEAN_DATE | awk -F'-' '{print $1}'`
  month=`echo $CLEAN_DATE | awk -F'-' '{print $2}'`
  dayOfMonth=`echo $CLEAN_DATE | awk -F'-' '{print $3}'`

   if [ "$dayOfMonth" == "" ]; then
    if [ "$month" == "" ]; then
      if [ "$year" == "" ]; then
        echo "Syncing EVERYTHING!!!"
        if [[ "$_src" == "s3://"* ]]; then
          aws s3 sync --force-glacier-transfer --size-only --exclude "$IGNORED_FILES" "$_src" "$_dst"
        else
          rsync -avz "$_src" "$_dst"
        fi
      else
        echo "Syncing whole year: $year"
        if [[ "$_src" == "s3://"* ]]; then
          aws s3 sync --force-glacier-transfer --size-only --exclude "$IGNORED_FILES" "$_src/$year" "$_dst/$year"
        else
          rsync -avz "$_src/$year" "$_dst"
        fi
      fi
    else
      echo "Syncing whole month: $year-$month"
      if [[ "$_src" == "s3://"* ]]; then
        aws s3 sync --force-glacier-transfer --size-only --exclude "*" --include "$year-$month-*/*" --exclude "$IGNORED_FILES" "$_src/$year" "$_dst/$year"
      else
        rsync -avz --include=\"$year-$month-*/*\" --exclude="*" "$_src/$year/" "$_dst/$year"
      fi
    fi
  else
    echo "Syncing date: $year-$month-$dayOfMonth"
    if [[ "$_src" == "s3://"* ]]; then
      aws s3 sync --force-glacier-transfer --size-only --exclude "$IGNORED_FILES" "$_src/$year/$year-$month-$dayOfMonth" "$_dst/$year"
    else
      rsync -avz "$_src/$year/$year-$month-$dayOfMonth" "$_dst/$year"
    fi
  fi
}

if [[ $(which aws) == "" ]]; then
  echo "\"awscli\" not found. Installing..."
  pip install awscli
fi

subcommand=$1
shift

case "$subcommand" in
  init)
    while test $# -gt 0; do
      case $1 in
      -h|--help)
        printf 'Usage: %s init [--(no-)backups] [--(no-)previews] [-v|--verbose] [-h|--help] <src> <dst>\n' "$0"
        printf "\tExample: %s\n" "$0 init --no-previews \"s3://lightroom\" \"~/Pictures\""
        exit 1
        ;;
      -v|--verbose)
        VERBOSE=1
        ;;
      --no-backups|--backups)
        _arg_backups="on"
        test "${1:0:5}" = "--no-" && _arg_backups="off"
        ;;
      --no-previews|--previews)
        _arg_previews="on"
        test "${1:0:5}" = "--no-" && _arg_previews="off"
        ;;
      *)
        _positionals+=("$1")
        ;;
      esac
      shift
    done
    _positional_names=('_src' '_dst' )
    test ${#_positionals[@]} -lt 2 && _PRINT_HELP=yes die "FATAL ERROR: Not enough positional arguments - we require exactly 2, but got only ${#_positionals[@]}." 1
    test ${#_positionals[@]} -gt 2 && _PRINT_HELP=yes die "FATAL ERROR: There were spurious positional arguments --- we expect exactly 2, but got ${#_positionals[@]} (the last one was: '${_positionals[*]: -1}')." 1
    for (( ii = 0; ii < ${#_positionals[@]}; ii++))
    do
      eval "${_positional_names[ii]}=\${_positionals[ii]}" || die "Error during argument parsing, possibly an Argbash bug." 1
    done
    init
    ;;
    push)
    while test $# -gt 0; do
      _key="$1"
      case "$_key" in
        -h|--help )
          printf 'Usage: %s push [-h|--help] [-v|--verbose] <src> <dst>\n' "$0"
          printf "\tExample: %s\n" "$0 push \"~/Pictures\" \"s3://lightroom\""
          exit 1
          ;;
        -v|--verbose)
          VERBOSE=1
          ;;
        *)
          _positionals+=("$1")
          ;;
      esac
      shift
    done
    _positional_names=('_src' '_dst' )
    test ${#_positionals[@]} -lt 2 && _PRINT_HELP=yes die "FATAL ERROR: Not enough positional arguments - we require exactly 2, but got only ${#_positionals[@]}." 1
    test ${#_positionals[@]} -gt 2 && _PRINT_HELP=yes die "FATAL ERROR: There were spurious positional arguments --- we expect exactly 2, but got ${#_positionals[@]} (the last one was: '${_positionals[*]: -1}')." 1
    for (( ii = 0; ii < ${#_positionals[@]}; ii++))
    do
      eval "${_positional_names[ii]}=\${_positionals[ii]}" || die "Error during argument parsing, possibly an Argbash bug." 1
    done
    push
    ;;
  restore)
    while test $# -gt 0; do
      _key="$1"
      case "$_key" in
        -h|--help )
          printf 'Usage: %s restore [-h|--help] [-v|--verbose] [-d|--date <arg>] <bucket>\n' "$0"
          printf "\tExample: %s\n" "$0 restore -d 2014-07-13 \"lightroom-bucket\""
          exit 1
          ;;
        -v|--verbose)
          VERBOSE=1
          ;;
        -d|--date|--date=*)
          _val="${_key##--option=}"
          if test "$_val" = "$_key"
          then
            test $# -lt 2 && die "Missing value for the optional argument '$_key'." 1
            _val="$2"
            shift
          fi
          _arg_date="$_val"
          ;;
        *)
          _positionals+=("$1")
          ;;
      esac
      shift
    done
    _positional_names=('_bucket_name')
    test ${#_positionals[@]} -lt 1 && _PRINT_HELP=yes die "FATAL ERROR: Not enough positional arguments - we require exactly 2, but got only ${#_positionals[@]}." 1
    test ${#_positionals[@]} -gt 1 && _PRINT_HELP=yes die "FATAL ERROR: There were spurious positional arguments --- we expect exactly 2, but got ${#_positionals[@]} (the last one was: '${_positionals[*]: -1}')." 1
    for (( ii = 0; ii < ${#_positionals[@]}; ii++))
    do
      eval "${_positional_names[ii]}=\${_positionals[ii]}" || die "Error during argument parsing, possibly an Argbash bug." 1
    done
    restore
    ;;
  pull)
    while test $# -gt 0; do
      _key="$1"
      case "$_key" in
        -h|--help )
          printf 'Usage: %s pull [-h|--help] [-v|--verbose] [-d|--date <arg>] <src> <dst>\n' "$0"
          printf "\tExample: %s\n" "$0 pull -d 2014-07-13 \"s3://lightroom\" \"~/Pictures\""
          exit 1
          ;;
        -v|--verbose)
          VERBOSE=1
          ;;
        -d|--date|--date=*)
          _val="${_key##--option=}"
          if test "$_val" = "$_key"
          then
            test $# -lt 2 && die "Missing value for the optional argument '$_key'." 1
            _val="$2"
            shift
          fi
          _arg_date="$_val"
          ;;
        *)
          _positionals+=("$1")
          ;;
      esac
      shift
    done
    _positional_names=('_src' '_dst' )
    test ${#_positionals[@]} -lt 2 && _PRINT_HELP=yes die "FATAL ERROR: Not enough positional arguments - we require exactly 2, but got only ${#_positionals[@]}." 1
    test ${#_positionals[@]} -gt 2 && _PRINT_HELP=yes die "FATAL ERROR: There were spurious positional arguments --- we expect exactly 2, but got ${#_positionals[@]} (the last one was: '${_positionals[*]: -1}')." 1
    for (( ii = 0; ii < ${#_positionals[@]}; ii++))
    do
      eval "${_positional_names[ii]}=\${_positionals[ii]}" || die "Error during argument parsing, possibly an Argbash bug." 1
    done
    pull
    ;;
  *)
    _PRINT_HELP=yes die "Unknown subcommand \"$1\"" 1
    ;;
esac

exit 0



