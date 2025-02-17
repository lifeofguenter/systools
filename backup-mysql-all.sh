#!/usr/bin/env bash
#
# Author Günter Grodotzki <gunter@grodotzki.com>
#
# Changelog:
# 20250105 - Init
#

set -eo pipefail

### CONFIG ###

skip_dbs=( "information_schema" "mysql" "performance_schema" "sys" )
b2_bucket="onewerx-backups"

### DO NOT EDIT BELOW HERE ###

umask 077

consolelog() {
  logger -t "${0##*/}" "${1}"
}

skip_db() {
  local db
  for db in "${skip_dbs[@]}"; do
    if [[ "${db}" == "${1}" ]]; then
      return 0
    fi
  done
  return 1
}

backup_db() {
  local mysqldump_succeeded

  for i in {1..5}; do
    if mysqldump \
      --single-transaction \
      --quick \
      --routines \
      --triggers \
      --default-character-set=utf8mb4 \
      "${1}" > "mysqldump-${1}.sql"; then
      mysqldump_succeeded="1"
      break
    fi
    consolelog "* retrying ${1} [${i}/5]..."
  done

  if [[ -z "${mysqldump_succeeded}" ]]; then
    return 1
  fi

  rm -f "mysqldump-${1}.tar" "mysqldump-${1}.tar.gz"
  tar cf "mysqldump-${1}.tar" "mysqldump-${1}.sql"
  rm -f "mysqldump-${1}.sql"
  pigz "mysqldump-${1}.tar"
  return 0
}

upload_backup() {
  # only supported in b2 2.2+ (https://github.com/Backblaze/B2_Command_Line_Tool/issues/665)
  backblaze-b2 authorize-account "${B2_APPLICATION_KEY_ID}" "${B2_APPLICATION_KEY}" > /dev/null
  backblaze-b2 upload-file --noProgress "${b2_bucket}" "mysqldump-${2}.tar.gz" "mysqldumps/${1}/${2}/mysqldump-${2}-$(date +%Y-%m-%d).tar.gz" > /dev/null
}

# MAIN #

required_programs=( "mysql" "pigz" "tar" "backblaze-b2" )
for program in "${required_programs[@]}"; do
  if ! command -v "${program}" >/dev/null 2>&1; then
    consolelog "${program} is not installed but required."
    missing_programs="1"
  fi
done
if [[ -n "${missing_programs}" ]]; then
  exit 1
fi

if [[ -z "${B2_APPLICATION_KEY_ID}" ]] || [[ -z "${B2_APPLICATION_KEY}" ]]; then
  consolelog "Both B2_APPLICATION_KEY_ID and B2_APPLICATION_KEY need to be set."
  exit 1
fi

if [[ -n "${1}" ]]; then
  prefix="${1}"
else
  prefix="daily"
fi

for db in $(mysql -NBe 'SHOW DATABASES;'); do
  if skip_db "${db}"; then
    continue
  fi

  consolelog "Backing up ${db}"
  if ! backup_db "${db}"; then
    consolelog "...failed mysqldump for ${db}!"
    continue
  fi

  if ! upload_backup "${prefix}" "${db}"; then
    consolelog "..failed b2 for ${db}!"
    continue
  fi
done
