#!/bin/bash
#
# Author: Gunter Grodotzki (gunter@grodotzki.co.za)
# Version: 2015-11-20
#
# Pipe MySQL dumps to S3.

set -e

__DIR__="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# required libs
source "${__DIR__}/shlib/variables.shlib"


# check if required vars were set
if ! variables::isset MYSQL_HOST MYSQL_USER MYSQL_PASS MYSQL_DB AWS_PROFILE S3_BUCKET FILE_PREFIX; then
  echo 'Please make sure that the following envvars are set:' 1>&2
  echo '' 1>&2
  echo 'MYSQL_HOST' 1>&2
  echo 'MYSQL_USER' 1>&2
  echo 'MYSQL_PASS' 1>&2
  echo 'MYSQL_DB' 1>&2
  echo 'AWS_PROFILE' 1>&2
  echo 'S3_BUCKET' 1>&2
  echo 'FILE_PREFIX' 1>&2
  exit 1
fi

filename="${FILE_PREFIX}-$(date +%Y-%m-%d).zip"

mysqldump \
-h"${MYSQL_HOST}" \
-u"${MYSQL_HOST}" \
-p"${MYSQL_HOST}" \
"${MYSQL_DB}" | zip "${filename}" -

aws \
--profile "${AWS_PROFILE}" \
--output text \
s3 cp "${filename}" "s3://${S3_BUCKET}"

rm "${filename}"