#!/bin/bash
#
# Author: Gunter Grodotzki (gunter@grodotzki.co.za)
# Version: 2015-12-21
#
# Pipe MySQL dumps to b2.

set -e

__DIR__="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# required libs
source "${__DIR__}/shlib/variables.shlib"


# check if required vars were set
if ! variables::isset MYSQL_HOST MYSQL_USER MYSQL_PASS MYSQL_DB B2_BUCKET B2_FOLDER FILE_PREFIX NUM_BACKUPS; then
  echo 'Please make sure that the following envvars are set:' 1>&2
  echo '' 1>&2
  echo 'MYSQL_HOST'  1>&2
  echo 'MYSQL_USER'  1>&2
  echo 'MYSQL_PASS'  1>&2
  echo 'MYSQL_DB'    1>&2
  echo 'B2_BUCKET'   1>&2
  echo 'B2_FOLDER'   1>&2
  echo 'FILE_PREFIX' 1>&2
  echo 'NUM_BACKUPS' 1>&2
  exit 1
fi

#
# create new backup
#

filename="${FILE_PREFIX}-$(date +%Y-%m-%d).tar.xz"

mysqldump -C \
-h"${MYSQL_HOST}" \
-u"${MYSQL_USER}" \
-p"${MYSQL_PASS}" \
"${MYSQL_DB}" > dump.sql

tar cfJ "${filename}" dump.sql

rm dump.sql

b2 upload_file "${B2_BUCKET}" "${filename}" "${B2_FOLDER}/${filename}"

rm "${filename}"


#
# purge older backups
#

# get a list of all files
b2 ls --long "${B2_BUCKET}" "${B2_FOLDER}" |
# we are only interested in our backps
grep "${FILE_PREFIX}" |
# squash repeating spaces
tr -s ' ' |
# sort by (and only by) the 3rd column DESC (will show newest files first)
sort -k3,3r |
# loop through the results
while read -r each_id each_status each_date each_time each_size each_file; do
  n=$((n + 1))

  # delete older snapshots after the desired amount is reached
  if [ "${n}" -gt "${NUM_BACKUPS}" ]; then
    echo "[Deleting] ${each_file} - ${each_date}"
    b2 delete_file_version "${each_file}" "${each_id}"
  fi
done

exit 0