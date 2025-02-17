remote_exec() {
  local ret
  local cmd
  local conn
  local port

  args=()

  if [[ -n "${SSH_JUMP_HOST}" ]]; then
    args+=("-J ${SSH_JUMP_HOST}")
  fi

  # support user@host#port
  if [[ "${1}" == *"#"* ]]; then
    conn="${1%#*}"
    port="${1##*#}"
  else
    conn="${1}"
    port=22
  fi

  # switch between osx vs. linux base64
  if ! base64 --version &> /dev/null || ! base64 --version | grep -qF 'coreutils'; then
    cmd="$(echo "${2}" | base64)"
  else
    cmd="$(echo "${2}" | base64 -w0)"
  fi

  if [[ -n "${3}" ]]; then
    ret="$(sshpass -p "${3}" ssh \
      -p "${port}" \
      -o PreferredAuthentications=password \
      -o PubkeyAuthentication=no \
      -o StrictHostKeyChecking=no \
      -n "${conn}" \
      "${args[@]}" \
      "echo '${cmd}' | base64 -d | bash")"
  else
    ret="$(ssh \
      -p "${port}" \
      -o StrictHostKeyChecking=no \
      -n "${conn}" \
      "${args[@]}" \
      "echo '${cmd}' | base64 -d | bash")"
  fi

  echo "${ret}"
}
