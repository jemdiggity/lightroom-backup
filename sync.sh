#!/bin/bash
SUCCESS=0
FAILURE=1

CLEAN_DATE=""

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
  [ "$DIR_LOCAL" == "" ] && return $FAILURE
  [ "$DIR_REMOTE" == "" ] && return $FAILURE
  
  #Remove trailing slash for non-weird behaviour with sync program
  DIR_LOCAL=${DIR_LOCAL%/}
  DIR_REMOTE=${DIR_REMOTE%/}
  return $SUCCESS
}

function init {
  # Copy Lightroom database into local dir.
  check_options || return $FAILURE
  
  cp -av "$DIR_REMOTE/Lightroom" "$DIR_LOCAL"
}

function push {
  # Sync local dir to remote dir
  check_options || return $FAILURE
  
  if [[ "$DIR_REMOTE" == "s3://"* ]]; then
    aws s3 sync --size-only "$DIR_LOCAL" "$DIR_REMOTE"
  else
  	rsync -avz "$DIR_LOCAL" "$DIR_REMOTE"
  fi
  
}

function pull {
  check_options || return $FAILURE
  
  date=$TARGET_DATE
  
  date_check "$date" || return $FAILURE
  
  year=`echo $CLEAN_DATE | awk -F'-' '{print $1}'`
  month=`echo $CLEAN_DATE | awk -F'-' '{print $2}'`
  dayOfMonth=`echo $CLEAN_DATE | awk -F'-' '{print $3}'`

  mkdir -p $DIR_LOCAL/$year
  
  if [ "$dayOfMonth" == "" ]; then
    if [ "$month" == "" ]; then
      if [ "$year" == "" ]; then
        echo "Syncing EVERYTHING!!!"
        if [[ "$DIR_REMOTE" == "s3://"* ]]; then
          aws s3 sync --size-only "$DIR_REMOTE" "$DIR_LOCAL"
        else
          rsync -avz "$DIR_REMOTE" "$DIR_LOCAL"
        fi
      else
        echo "Syncing whole year: $year"
        if [[ "$DIR_REMOTE" == "s3://"* ]]; then
          aws s3 sync --size-only "$DIR_REMOTE/$year" "$DIR_LOCAL"
        else
          rsync -avz "$DIR_REMOTE/$year" "$DIR_LOCAL"
        fi
      fi
    else
      echo "Syncing whole month: $year-$month"
      if [[ "$DIR_REMOTE" == "s3://"* ]]; then
        aws s3 sync --size-only --include="/$year" --include="/$year/$year-$month-*" --include="/$year/$year-$month-*/*" --exclude="*" "$DIR_REMOTE/$year" "$DIR_LOCAL"
      else
        rsync -avz --include="/$year" --include="/$year/$year-$month-*" --include="/$year/$year-$month-*/*" --exclude="*" "$DIR_REMOTE/$year" "$DIR_LOCAL"
      fi
    fi
  else
    echo "Syncing date: $year-$month-$dayOfMonth"
    if [[ "$DIR_REMOTE" == "s3://"* ]]; then
      aws s3 sync --size-only "$DIR_REMOTE/$year/$year-$month-$dayOfMonth" "$DIR_LOCAL/$year"
    else
      rsync -avz "$DIR_REMOTE/$year/$year-$month-$dayOfMonth" "$DIR_LOCAL/$year"
    fi
  fi
}

while [[ $# -gt 0 ]]
do
key="$1"
           
case $key in
  '--remote')
  DIR_REMOTE="$2"
  shift
  ;;
  
  '--local')
  DIR_LOCAL="$2"
  shift
  ;;
  
  '--date')
  TARGET_DATE="$2"
  shift
  ;;

	'init')
  echo "Initializing from $DIR_REMOTE to $DIR_LOCAL"
  init
	;;
    
	'push')
  echo "Pushing to $DIR_REMOTE from $DIR_LOCAL"
  push
	;;
  
 	'pull')
  echo "Pulling from $DIR_REMOTE to $DIR_LOCAL"
  pull
	;;
  
  *)
    echo $"Usage: $0 [options] {init|push|pull}"
    echo $"Example: $0 --local ~/Pictures --remote /Volumes/Jeremy/Pictures --date 2016-07-07 pull"
    echo $"Example: $0 --local /Volumes/Jeremy/Pictures --s3 s3://lightroom.jemdiggity push"
    echo $"Example: $0 --local ~/Pictures --remote /Volumes/Jeremy/Pictures init"
    exit 1
  ;;
esac
shift # past argument or value
done

exit 0



