#!/bin/bash
#
# Author: Gunter Grodotzki <gunter@grodotzki.co.za>
# Version: 2015-11-10
#
# Create vhosts configurations for Apache2.4 or Nginx 1.9

set -e

# display usage information
usage() {
  echo "Usage: $(basename ${0}) [OPTION]..." 1>&2
  echo "Create vhost for Apache 2.4 or Nginx 1.9 (+PHP-FPM)" 1>&2
  echo "" 1>&2
  echo "Options:" 1>&2
  echo "    -h    hostname" 1>&2
  echo "    -a    path of authorized_keys file to use" 1>&2
  echo "    -p    port number of php-fpm" 1>&2
  exit 1
}

while getopts ":h:a:p:" o; do
  case "${o}" in
  h)
    h=${OPTARG}
    ;;
  a)
    a=${OPTARG}
    ;;
  p)
    p=${OPTARG}
    ;;
  *)
    usage
    ;;
  esac
done
shift $((OPTIND-1))

if [[ -z "${h}" ]] || [[ ! -f "${a}" ]] || [[ -z "${p}" ]]; then
  usage
fi

u=${h//./_}

# prerequisites
if [[ ! -d /etc/nginx/vhosts ]]; then
  sudo mkdir /etc/nginx/vhosts
  sudo chown root: /etc/nginx/vhosts
fi

sudo useradd -d /var/www/${h} -m -G sftponly -s /usr/sbin/nologin ${u}
sudo chown root: /var/www/${h}
sudo mkdir /var/www/${h}/www/ /var/www/${h}/logs/ /var/www/${h}/.ssh/
sudo touch /var/www/${h}/logs/error.log
sudo cp ${a} /var/www/${h}/.ssh/
sudo chown -R ${u}: /var/www/${h}/*
sudo chown -R ${u}: /var/www/${h}/.ssh/
sudo chmod 750 /var/www/${h}/.ssh/
sudo chmod 640 /var/www/${h}/.ssh/`basename ${a}`

cat <<EOF | sudo tee -a /etc/php-fpm.conf > /dev/null

[${u}]
user = ${u}
group = ${u}
listen = 127.0.0.1:${p}
pm = ondemand
pm.max_children = 16
pm.process_idle_timeout = 60
request_terminate_timeout = 10m
chdir = /var/www/${h}/www
catch_workers_output = no
security.limit_extensions = .php
EOF

cat <<EOF | sudo tee -a /etc/php5/fpm/php.ini > /dev/null

[PATH=/var/www/${h}/]
open_basedir = "/var/www/${h}/www/:/tmp/:/usr/lib/php/:/usr/share/php/"
error_log = /var/www/${h}/logs/phperror.log
EOF
echo 'sudo /etc/init.d/php-fpm reload'

command -v nginx > /dev/null 2>&1
if [[ "${?}" == "0" ]]
then
  cat <<EOF | sudo tee /etc/nginx/vhosts/${h}.conf > /dev/null
server {
  listen 80;
  server_name ${h} *.${h};

  root /var/www/${h}/www;
  index index.html index.htm index.php;

  error_log /var/www/${h}/logs/error.log error;

  # enable php
  location ~ [^/]\.php(/|$) {
    fastcgi_split_path_info ^(.+?\.php)(/.*)$;
    try_files \$uri =404;

    fastcgi_pass 127.0.0.1:${p};
    fastcgi_index index.php;
    include fastcgi.conf;
  }
}
EOF

  echo 'sudo /etc/init.d/nginx reload'
else
  cat <<EOF | sudo tee /etc/apache2/sites-available/${h}.conf > /dev/null
<VirtualHost *:80>
  ServerName ${h}
  ServerAlias *.${h}

  DocumentRoot /var/www/${h}/www
  <Directory /var/www/${h}/www>
    AllowOverride All
    Require all granted
  </Directory>

  # PHP
  ProxyPassMatch ^/(.*\\.php(/.*)?)$ fcgi://127.0.0.1:${p}/var/www/${h}/www/\$1
  DirectoryIndex index.html index.htm index.php

  ErrorLog /var/www/${h}/logs/error.log
</VirtualHost>
EOF

  echo "sudo a2ensite ${h}"
  echo 'sudo /etc/init.d/apache2 reload'
fi
