#!/bin/bash
#
# Author: Gunter Grodotzki (gunter@grodotzki.co.za)
# Version: 2015-12-29
#
# Purge older files from b2.
# Required envvars:
# - B2_BUCKET:   the b2 bucketname to connect to
# - B2_FOLDER:   the folder within the bucket to search
# - FILE_PREFIX: will grep for this value (and ignore other files)
# - NUM_BACKUPS: num of files we want to keep

set -e

# display usage information
usage() {
  echo "Usage: $(basename ${0}) [OPTION]..."        1>&2
  echo "b2 file purger/rotator"                     1>&2
  echo ""                                           1>&2
  echo "Options:"                                   1>&2
  echo "    -b    b2 bucket name"                   1>&2
  echo "    -d    b2 directory/folder"              1>&2
  echo "    -f    filter (whitelist)"               1>&2
  echo "    -n    num of files to keep (newest)"    1>&2
  exit 1
}

# getopts
while getopts ":b:d:f:n:" o; do
  case "${o}" in
  b)
    b2_bucket=${OPTARG}
    ;;
  d)
    b2_folder=${OPTARG}
    ;;
  f)
    file_filter=${OPTARG}
    ;;
  n)
    num_files=${OPTARG}
    ;;
  *)
    usage
    ;;
  esac
done
shift $((OPTIND-1))

if [[ -z "${b2_bucket}" ]] || [[ -z "${b2_folder}" ]] || [[ -z "${num_files}" ]]; then
  usage
fi

# get a list of all files
b2 ls --long "${b2_bucket}" "${b2_folder}" |
# we are only interested in our backps
grep "${file_filter}" |
# squash repeating spaces
tr -s ' ' |
# sort by (and only by) the 3rd column DESC (will show newest files first)
sort -k3,3r |
# loop through the results
while read -r each_id each_status each_date each_time each_size each_file; do
  n=$((n + 1))

  # delete older snapshots after the desired amount is reached
  if [ "${n}" -gt "${num_files}" ]; then
    echo "[Deleting] ${each_file} - ${each_date}"
    b2 delete_file_version "${each_file}" "${each_id}"
  fi
done

exit 0