#!/bin/bash
#
# Author: Gunter Grodotzki (gunter@grodotzki.co.za)
# Version: 2015-11-25
#
# AWS VPC SecurityGroups updater for dynamic IPs.

set -e

# display usage information
usage() {
  echo "Usage: $(basename ${0}) [OPTION]..."        1>&2
  echo "aws sg ingress client"                      1>&2
  echo ""                                           1>&2
  echo "Options:"                                   1>&2
  echo "    -u    aws-cli profile name (optional)"  1>&2
  echo "    -l    space separated list of sg IDs"   1>&2
  echo "    -p    port number"                      1>&2
  echo "    -f    force update"                     1>&2
  exit 1
}

#
# Prerequisites
#

# dependencies
dependencies=( curl getopts aws logger )
for dependency in "${dependencies[@]}"; do
  if ! command -v ${dependency} > /dev/null 2>&1; then
    echo "Please install '${dependency}' first."
    exit 1
  fi
done

# getopts
while getopts ":u:l:p:f" o; do
  case "${o}" in
  u)
    profile=${OPTARG}
    ;;
  l)
    sgroups=${OPTARG}
    ;;
  p)
    port=${OPTARG}
    ;;
  f)
    force=1
    ;;
  *)
    usage
    ;;
  esac
done
shift $((OPTIND-1))

if [[ -z "${sgroups}" ]] || [[ -z "${port}" ]]; then
  usage
fi

if [[ -z "${profile}" ]]; then
  profile=default
fi

if [[ ! -d ~/.config/dyn_ingress ]]; then
  mkdir -p ~/.config/dyn_ingress
fi

#
# determine if IP changed
#
if ! current_ip=$(curl --silent --fail --max-time 30 --connect-timeout 5 --retry 3 --retry-delay 3 --compressed http://curlmyip.net); then
  logger -st dyn_ingress "Unable to reach curlmyip.net."
  exit 1
fi

last_ip_file="~/.config/dyn_ingress/lastip_${profile}"
last_ip=

if [[ ! -s ${last_ip_file} ]]; then
  echo -n ${current_ip} > ${last_ip_file}
else
  last_ip=$(cat ${last_ip_file})
fi

if [[ "${last_ip}" != "${current_ip}" ]] || [[ ! -z "${force}" ]]; then
  echo "Updating security group(s):"

  read -ra list <<< "${sgroups}"
  for sgroup in "${list[@]}"; do
    echo "  - ${sgroup}"

    # delete last_ip entry (if it exists)
    if [[ ! -z "${last_ip}" ]] && aws --profile "${profile}" --output text ec2 describe-security-groups --group-ids "${sgroup}" | grep ${last_ip} > /dev/null; then
      aws --profile "${profile}" ec2 revoke-security-group-ingress --group-id "${sgroup}" --protocol tcp --port ${port} --cidr "${last_ip}/32"
    fi

    # add current_ip entry
    aws --profile "${profile}" ec2 authorize-security-group-ingress --group-id "${sgroup}" --protocol tcp --port ${port} --cidr "${current_ip}/32"
  done

  # update last_ip
  echo -n ${current_ip} > ${last_ip_file}
else
  echo "Your IP did not change."
fi

exit 0