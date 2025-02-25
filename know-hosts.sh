#!/usr/bin/env bash

readlink_bin="${READLINK_PATH:-readlink}"
if ! "${readlink_bin}" -f test &> /dev/null; then
  __DIR__="$(dirname "$(python3 -c "import os,sys; print(os.path.realpath(os.path.expanduser(sys.argv[1])))" "${0}")")"
else
  __DIR__="$(dirname "$("${readlink_bin}" -f "${0}")")"
fi

source "${__DIR__}/libs/functions.lib.sh"
source "${__DIR__}/libs/remote_exec.lib.sh"

set -E
trap 'throw_exception' ERR

add_to_inventory() {
  for host in "${@}"; do
    consolelog "adding ${host} to inventory..."

    bofh_user_exists="$(remote_exec "${SSH_USER}@${host}#${SSH_PORT}" "id -u bofh 2> /dev/null || echo error" "${ssh_pass}")"

    # install sudo (assumes logged in as root)
    remote_exec "${SSH_USER}@${host}#${SSH_PORT}" "dpkg -l | grep sudo || (apt-get -qq update && DEBIAN_FRONTEND=noninteractive apt-get -y -qq install sudo)" "${ssh_pass}"

    if [[ -z "${ssh_pass}" ]]; then
      echo "[${host}]:${SSH_PORT} ansible_user=${SSH_USER} ansible_python_interpreter=${PYTHON_BIN:-/usr/bin/python3}" >> inventory-temp

      remote_exec "${SSH_USER}@${host}#${SSH_PORT}" "sudo DEBIAN_FRONTEND=noninteractive apt-get -y -qq install python3 python3-apt"
      if [[ "${SSH_USER}" != "bofh" ]] && [[ "${bofh_user_exists}" == "error" ]]; then
        remote_exec "${SSH_USER}@${host}#${SSH_PORT}" "id -u bofh || sudo useradd -d /home/bofh -m -s /bin/bash bofh"
      fi
    else
      echo "[${host}]:${SSH_PORT} ansible_user=${SSH_USER} ansible_password=${ssh_pass} ansible_become_password=${ssh_pass} ansible_python_interpreter=${PYTHON_BIN:-/usr/bin/python3}" >> inventory-temp
      printf '[ssh_connection]\nssh_args = -o PreferredAuthentications=password -o PubkeyAuthentication=no\n' > ansible.cfg

      remote_exec "${SSH_USER}@${host}#${SSH_PORT}" "echo '${ssh_pass}' | sudo -S DEBIAN_FRONTEND=noninteractive apt-get -y -qq install python3 python3-apt" "${ssh_pass}"
      if [[ "${SSH_USER}" != "bofh" ]] && [[ "${bofh_user_exists}" == "error" ]]; then
        remote_exec "${SSH_USER}@${host}#${SSH_PORT}" "echo '${ssh_pass}' | sudo -S useradd -d /home/bofh -m -s /bin/bash bofh" "${ssh_pass}"
      fi
    fi
  done
}

add_to_known_hosts() {
  local host_ip

  for host in "${@}"; do
    consolelog "adding ${host} to known_hosts..."
    host_ip="$(dig +short "${host}")"
    ssh-keygen -f ~/.ssh/known_hosts -R "${host}" &> /dev/null
    ssh-keygen -f ~/.ssh/known_hosts -R "${host_ip}" &> /dev/null
    ssh-keyscan -T 30 -p "${SSH_PORT}" "${host}" >> ~/.ssh/known_hosts 2> /dev/null
  done
}

usage() {
cat <<EOF
Usage: ${0##*/} [OPTIONS] TASK HOSTS...
bootstrap ansible hosts

Options:
    -h              display this help and exit
    -u              initial ssh user (default: bofh)
    -p              ssh-port to use (default: 22)
    -J              jump host (default: none)

Tasks:
    known-hosts     add HOSTS to known_hosts
    bootstrap       bootstrap HOSTS
EOF
}

OPTIND=1

while getopts "hu:p:J:" opt; do
  case "${opt}" in
    h )
      usage
      exit 0
      ;;
    u )
      SSH_USER="${OPTARG}"
      ;;
    p )
      SSH_PORT="${OPTARG}"
      ;;
    J )
      SSH_JUMP_HOST="${OPTARG}"
      ;;
    '?' )
      usage >&2
      exit 1
      ;;
  esac
done
shift "$((OPTIND-1))"

if [[ -z "${SSH_USER}" ]]; then
  SSH_USER="bofh"
fi

if [[ -z "${SSH_PORT}" ]]; then
  SSH_PORT="22"
fi

# tasks
task="${1}"
shift

case "${task}" in
  known-hosts )
    add_to_known_hosts "${@}"
    ;;

  bootstrap )
    read -rsp "optional ssh password for '${SSH_USER}' (hidden): " ssh_pass
    echo ""

    ssh_keys=()
    while :; do
      read -p "ssh pubkey: " ssh_key
      if [[ -z "${ssh_key}" ]]; then
        break
      else
        ssh_keys+=( "${ssh_key}" )
      fi
    done

    rm -f inventory-temp ansible.cfg
    add_to_inventory "${@}"

    # install minimal required packages
    ansible all -i inventory-temp -m ansible.builtin.apt -ba "name=acl update_cache=yes cache_valid_time=3600" -e 'ansible_python_interpreter=/usr/bin/python3'

    # password-less sudoer
    ansible all -i inventory-temp -m lineinfile -ba "path=/etc/sudoers.d/100-no-pass-users line='bofh ALL=(ALL) NOPASSWD:ALL' create=yes mode=0440 validate='/usr/sbin/visudo -cf %s'" -e 'ansible_python_interpreter=/usr/bin/python3'
    ansible all -i inventory-temp -m lineinfile -ba "path=/etc/sudoers.d/100-no-pass-users line='Defaults:bofh "'!'"requiretty' create=yes mode=0440 validate='/usr/sbin/visudo -cf %s'" -e 'ansible_python_interpreter=/usr/bin/python3'

    # create .ssh
    ansible all -i inventory-temp -m file --become-user=bofh -ba "path=~/.ssh mode=0750 state=directory" -e 'ansible_python_interpreter=/usr/bin/python3'
    for ssh_key in "${ssh_keys[@]}"; do
      ansible all -i inventory-temp -m lineinfile --become-user=bofh -ba "path=~/.ssh/authorized_keys create=yes mode=0640 line='${ssh_key}'" -e 'ansible_python_interpreter=/usr/bin/python3'
    done

    # cleanup
    rm -f inventory-temp ansible.cfg
    ;;
esac

#remote_exec "bofh@${host}" "{ sleep 2; sudo reboot; } >/dev/null &"
#ansible all -i inventory -m command -ba 'whoami'
