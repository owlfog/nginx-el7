# NGINX RPM для CentOS 7

Локальная сборка внутреннего RPM `nginx` для EL7/CentOS 7. По умолчанию
собирается `nginx-1.30.2`, но версия задается параметром `VERSION`.

## Быстрый старт

```bash
make rpm
make smoke
make repo
```

Полный прогон одной командой:

```bash
make all
```

Результаты:

- RPM: `dist/rpms/`
- SRPM: `dist/srpms/`
- локальный yum-репозиторий: `dist/repo/el7/x86_64/`
- директория для GitHub Pages: `public/`
- публичный GPG-ключ после подписи: `dist/RPM-GPG-KEY-rosa-khutor`

Сборка другой версии:

```bash
make rpm VERSION=1.30.3 RELEASE=1
```

## Что внутри

- `docker/Dockerfile.el7` - build image на базе `centos:7` с CentOS Vault.
- `packaging/SPECS/nginx.spec.in` - spec для внутреннего RPM.
- `packaging/SOURCES/` - systemd unit, дефолтный `nginx.conf`, vhost, logrotate.
- `scripts/build-rpm.sh` - скачивает архив с nginx.org, проверяет PGP-подпись и запускает `rpmbuild`.
- `scripts/create-repo.sh` - создает локальный yum-репозиторий через `createrepo`.
- `scripts/build-pages.sh` - готовит `public/` для GitHub Pages.
- `scripts/sign-rpms.sh` - подписывает RPM/SRPM внутренним GPG-ключом.
- `scripts/sign-repo.sh` - подписывает `repodata/repomd.xml`.
- `scripts/smoke-test-rpm.sh` - ставит RPM в EL7-контейнер и выполняет `nginx -V` / `nginx -t`.

## Совместимость с текущим конфигом

Текущий боевой конфиг загружает динамические модули:

- `load_module modules/ngx_http_geoip_module.so`
- `load_module modules/ngx_http_perl_module.so`

Поэтому сборка выпускает дополнительные RPM:

- `nginx-module-geoip`
- `nginx-module-perl`

Ставить их нужно вместе с основным пакетом:

```bash
yum install \
  nginx-1.30.2-1.el7.rhcustom \
  nginx-module-geoip-1.30.2-1.el7.rhcustom \
  nginx-module-perl-1.30.2-1.el7.rhcustom
```

Остальные найденные директивы покрыты основной сборкой: `realip`, `stub_status`,
`http_v2`, `mp4`, `flv`, `secure_link`, `auth_request`, `slice`, `dav`.

RPM с модулем GeoIP содержит только сам модуль. Файлы баз из текущего конфига
`/etc/nginx/GeoIP.dat` и `/etc/nginx/GeoIPCity.dat` нужно сохранить на сервере
или выпустить отдельным внутренним RPM с базами GeoIP.

## Проверка источника

По умолчанию `scripts/build-rpm.sh` скачивает:

- `https://nginx.org/download/nginx-$VERSION.tar.gz`
- `https://nginx.org/download/nginx-$VERSION.tar.gz.asc`
- публичные ключи с `https://nginx.org/en/pgp_keys.html`

И выполняет `gpg --verify`. Для временной локальной отладки можно отключить:

```bash
NGINX_VERIFY_PGP=0 make rpm
```

В CI лучше оставить проверку включенной и дополнительно фиксировать `NGINX_SHA256`.

## Подпись RPM и yum-репозитория

Для боевого репозитория нужен внутренний GPG-ключ. Рекомендуемый порядок:

```bash
make rpm
RPM_GPG_NAME="Rosa Khutor RPM Signing" make sign-rpms
make repo
RPM_GPG_NAME="Rosa Khutor RPM Signing" make sign-repo
```

В GitHub Actions приватный ключ передается через repository secret
`RPM_GPG_PRIVATE_KEY_B64`, а публичный ключ публиковать рядом с repo:
`dist/RPM-GPG-KEY-rosa-khutor`.

Важно: RPM нужно подписывать до `createrepo`, потому что подпись меняет содержимое
RPM, а значит и checksum в metadata.

До выполнения `make sign-rpms` проверка `rpm -K` покажет только `digests OK`.
После подписи `scripts/sign-rpms.sh` импортирует публичный ключ во временную
rpmdb под `build/gnupg-sign/rpmdb` и проверяет подписи через нее; системный
rpmdb контейнера не меняется.
Для боевой выкладки должны быть подписаны и RPM/SRPM, и `repodata/repomd.xml`.
Если ключ подписи защищен passphrase, в CI нужен заранее настроенный `gpg-agent`;
практичный вариант для protected runner - отдельный signing subkey без
passphrase, хранящийся только в repository secret GitHub.

Фрагмент `.repo`:

```ini
[rosa-nginx-el7]
name=Rosa Khutor NGINX EL7
baseurl=https://<github-owner>.github.io/<github-repo>/el7/x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://<github-owner>.github.io/<github-repo>/RPM-GPG-KEY-rosa-khutor
includepkgs=nginx nginx-module-*
```

## Публикация на GitHub Pages

Workflow `.github/workflows/pages.yml` собирает RPM, прогоняет smoke-test,
подписывает пакеты, создает yum metadata, подписывает `repomd.xml`, собирает
`public/` и публикует его в GitHub Pages.

Перед первым запуском в GitHub нужно:

- включить Pages с build source `GitHub Actions`;
- добавить repository secret `RPM_GPG_PRIVATE_KEY_B64`;
- при необходимости добавить variable `RPM_GPG_NAME`, по умолчанию используется `Rosa Khutor RPM Signing`;
- при custom domain добавить variable `PAGES_BASE_URL`, например `https://packages.example.org`.

Для обычного project Pages URL будет:

```text
https://<github-owner>.github.io/<github-repo>/
```

На CentOS 7 репозиторий подключается стандартно через `/etc/yum.repos.d`:

```bash
sudo rpm --import https://<github-owner>.github.io/<github-repo>/RPM-GPG-KEY-rosa-khutor
sudo curl -fsSL \
  -o /etc/yum.repos.d/rosa-nginx-el7.repo \
  https://<github-owner>.github.io/<github-repo>/rosa-nginx-el7.repo
sudo yum clean metadata
sudo yum install nginx nginx-module-geoip nginx-module-perl
```

Локально `public/` можно собрать так:

```bash
make signed-repo PAGES_BASE_URL=https://<github-owner>.github.io/<github-repo>
```

## Установка на CentOS 7

После подключения repo:

```bash
yum clean metadata
yum --showduplicates list nginx
yum install nginx nginx-module-geoip nginx-module-perl
nginx -t
systemctl reload nginx
```

Откат:

```bash
yum downgrade \
  nginx-1.30.1-1.el7.rhcustom \
  nginx-module-geoip-1.30.1-1.el7.rhcustom \
  nginx-module-perl-1.30.1-1.el7.rhcustom
# или
yum history undo <transaction_id>
```

## Важные ограничения

Сборка использует системный OpenSSL из CentOS 7. Это минимизирует риск
несовместимости с ОС, но не дает TLS 1.3 и новые crypto-возможности OpenSSL 1.1+.

Перед боевой выкладкой нужно сравнить текущий `nginx -V` на сервере с
нашим `nginx -V`, особенно если используются сторонние динамические модули.
