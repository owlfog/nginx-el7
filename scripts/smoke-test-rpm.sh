#!/usr/bin/env bash
set -euo pipefail

RELEASE_SUFFIX="${RELEASE_SUFFIX:-rhcustom}"
RPM_FILE="$(find dist/rpms -maxdepth 1 -type f -name "nginx-[0-9]*.${RELEASE_SUFFIX}.*.rpm" | sort | tail -n 1)"
MODULE_RPM_FILES=()

if [[ -z "$RPM_FILE" ]]; then
  echo "No RPM file matching dist/rpms/nginx-[0-9]*.${RELEASE_SUFFIX}.*.rpm" >&2
  exit 1
fi

while IFS= read -r module_rpm; do
  MODULE_RPM_FILES+=("$module_rpm")
done < <(find dist/rpms -maxdepth 1 -type f -name "nginx-module-*.${RELEASE_SUFFIX}.*.rpm" | sort)

yum -y localinstall "$RPM_FILE" "${MODULE_RPM_FILES[@]}"
nginx -V
nginx -t

if [[ -f /usr/lib64/nginx/modules/ngx_http_geoip_module.so && -f /usr/lib64/nginx/modules/ngx_http_perl_module.so ]]; then
  GEOIP_COUNTRY_DB="/usr/share/GeoIP/GeoIP.dat"
  GEOIP_CITY_DB="/usr/share/GeoIP/GeoIPCity.dat"
  COMPAT_CONFIG="/tmp/nginx-compat.conf"

  {
    echo "load_module modules/ngx_http_geoip_module.so;"
    echo "load_module modules/ngx_http_perl_module.so;"
    echo "events { worker_connections 16; }"
    echo "http {"
    [[ -f "$GEOIP_COUNTRY_DB" ]] && echo "    geoip_country $GEOIP_COUNTRY_DB;"
    [[ -f "$GEOIP_CITY_DB" ]] && echo "    geoip_city $GEOIP_CITY_DB;"
    echo "    perl_set \$lower_uri 'sub { return lc(\$_[0]->uri); }';"
    echo "    server {"
    echo "        listen 127.0.0.1:8080;"
    echo "        set_real_ip_from 127.0.0.1;"
    echo "        real_ip_header X-Real-IP;"
    echo "        location /status { stub_status; }"
    echo "        location /video.mp4 { mp4; }"
    echo "        location /video.flv { flv; }"
    echo "    }"
    echo "}"
  } > "$COMPAT_CONFIG"

  nginx -t -c "$COMPAT_CONFIG"
fi

rpm -ql nginx
