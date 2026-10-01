#!/bin/sh
set -eu
ns="$(awk '/^nameserver / { print $2; exit }' /etc/resolv.conf)"
if [ -z "${ns}" ]; then
  echo "no nameserver in /etc/resolv.conf" >&2
  exit 1
fi
case "${ns}" in
  *[!0-9.]*)
    echo "unexpected nameserver" >&2
    exit 1
    ;;
esac
sed "s/__NAMESERVER__/${ns}/g" /etc/nginx/nginx.conf.template > /tmp/nginx.conf
exec nginx -c /tmp/nginx.conf -g "daemon off;"
