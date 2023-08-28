#!/usr/bin/env bash
cd $(dirname $(readlink -f $0))
set -e;set +o pipefail
log() { echo $@ >&2; }
vv() { log "$@";"$@"; }
dup() { vv docker-compose up -d --no-deps $@; }
dupr() { vv dup --force-recreate $@; }
if [[ -z ${SKIP_STOP} ]];then
    vv docker-compose stop -t 0
    vv systemctl stop docker-huginn || true
fi
vv docker-compose stop -t 0 threaded huginn nginx || true
dup log setup-debian setup-services db dbs
if [[ -z ${SKIP_SYNC-} ]];then
vv docker-compose exec -T \
    -e SKIP_DB_RESET=${SKIP_DB_RESET-} \
    -e SKIP_FILES=${SKIP_FILES-} \
    db bash -i <<_EOF
set -e;set +o pipefail
log() { echo \$@ >&2; }
vv() { log "\$@";"\$@"; }
export DEBIAN_FRONTEND=noninteractive
pkgs=""
if ! (ssh -V >/dev/null 2>&1 );then pkgs="\$pkgs openssh-client";fi
if ! (rsync --version >/dev/null 2>&1 );then pkgs="\$pkgs rsync";fi
if [[ -n "\$pkgs" ]];then apt -yq update && apt install -yq \$pkgs;fi
if [[ -z \${SKIP_DB_RESET-} ]];then
  echo "loading huginn"
  ssh \$OLD_HUGINN_HOST mysqldump --defaults-file=/etc/mysql/debian.cnf -n --routines \
  --opt --quote-names --extended-insert --single-transaction \$OLD_MYSQL_DATABASE \
  | mysql --host 127.0.0.1 --user \$MYSQL_USER --password="\$MYSQL_PASSWORD" \$MYSQL_DATABASE
  echo "dumps loaded"
fi
if [[ -z \${SKIP_FILES-} ]];then
    for i in data/ log/;do
        d=/huginn-data/huginn/\$i
        [[ ! -d \$i ]] && mkdir -p \$i
        rsync -aAHv \$OLD_HUGINN_HOST:\${OLD_HUGINN_PATH}/\$i \$d
    done
fi
_EOF
fi
if [[ -z ${SKIP_FIXPERMS-} ]];then
set -x
docker-compose run --rm --entrypoint bash -u root huginn -exc \
    "cd /app;ls;chmod -R g-s data tmp log;chown -Rfv 1001 data tmp log"
fi
dupr huginn nginx
# vim:set et sts=4 ts=4 tw=0: 
