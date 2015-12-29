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
