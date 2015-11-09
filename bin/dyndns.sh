#!/bin/bash
#
# Author: Gunter Grodotzki <gunter@grodotzki.co.za>
# Version: 2015-11-10
#
# dyndns client

set -e

# display usage information
usage() {
  echo "Usage: $(basename ${0}) [OPTION]..." 1>&2
  echo "dyndns client" 1>&2
  echo "" 1>&2
  echo "Options:" 1>&2
  echo "    -k    key" 1>&2
  exit 1
}

# get current ip via curlmyip.net
get_ip() {
  local buf
  local ret
  buf=$(curl --silent --fail --max-time 30 --connect-timeout 10 --compressed http://curlmyip.net)
  ret=${?}
  if [[ "${ret}" != "0" ]]; then
    logger -i -t dyndnsbash "Unable to get public IP (Code: ${ret}). Try again later."
    exit 1
  fi
  echo ${buf}
}

# update current ip
update_ip() {
  local buf
  local ret
  buf=$(curl --silent --fail --max-time 30 --connect-timeout 10 --compressed "${update_url}")
  ret=${?}
  if [[ "${ret}" != "0" ]]; then
    logger -i -t dyndnsbash "Unable to update IP (Code: ${ret}):"
    logger -i -t dyndnsbash "${buf}"
    exit 1
  else
    logger -i -t dyndnsbash "${buf}"
  fi
}

while getopts ":k:" o; do
  case "${o}" in
  k)
    key=${OPTARG}
    ;;
  *)
    usage
    ;;
  esac
done
shift $((OPTIND-1))

if [[ -z "${k}" ]]; then
  usage
fi

# api url
update_url="http://freedns.afraid.org/dynamic/update.php?${key}"

# prerequisites
command -v curl >/dev/null 2>&1 || { logger -i -t dyndnsbash "Unable to find cURL. Aborting."; exit 1; }
mkdir -p /var/lib/dyndnsbash

# main:
current_ip=$(get_ip)
last_ip=

if [[ ! -s /var/lib/dyndnsbash/lastip ]]; then
  echo -n ${current_ip} > /var/lib/dyndnsbash/lastip
else
  last_ip=$(cat /var/lib/dyndnsbash/lastip)
fi

if [[ "${last_ip}" != "${current_ip}" ]]; then
  update_ip
  echo -n ${current_ip} > /var/lib/dyndnsbash/lastip
fi

exit 0
