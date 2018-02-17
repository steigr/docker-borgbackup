#!/usr/bin/env bash
# always fail
set -eo pipefail

__vars() {
    [[ -z "$HAS_VARS" ]] || return 0
    export HAS_VARS=1
    __borg_build_rsh
    __borg_build_archive
    __borg_build_passphrase
}

__debug() {
    set -x
}

__with_reaper() {
    TINI_SUBREAPER= exec tini -- "$0" "${@}"
}

__run_command() {
    [[ "${@}" ]] || set -- bash -l
    exec "${@}"
}

__mounted_volumes() {
    local filter="$1"
    grep -v \
        -e '^tmpfs ' \
        -e '^proc ' \
        -e '^devpts ' \
        -e '^shm ' \
        -e ' /sys/fs/cgroup/' \
        -e '^overlay ' \
        -e '^sysfs ' \
        -e '^mqueue ' \
        -e ' /etc/resolv.conf ' \
        -e ' /etc/hostname ' \
        -e ' /etc/hosts ' \
        /proc/mounts \
    | awk '{print $4 " " $2 }' \
    | while read opts mountpoint; do
        echo "$opts" | tr ',' '\n' | grep -q '^ro$' || continue
        if [[ "${filter:+x}" = "x" ]]; then
            test "$filter" "$mountpoint" \
            || continue
        fi
        echo "$mountpoint"
    done
}

__borg_build_rsh() {
    [[ -n "$BORG_RSH" ]] \
    || export BORG_RSH='ssh'
    
    [[ ! "$KNOWN_HOSTS" = "/dev/null" ]] \
    || export BORG_RSH="$BORG_RSH -o StrictHostKeyChecking=no"

    [[ -z "$KNOWN_HOSTS" ]] \
    || export BORG_RSH="$BORG_RSH -o UserKnownHostsFile=$KNOWN_HOSTS"

    [[ -z "$BORG_USER" ]] \
    || export BORG_RSH="$BORG_RSH -o User=$BORG_USER"

    [[ -z "$BORG_PORT" ]] \
    || export BORG_RSH="$BORG_RSH -o Port=$BORG_PORT"

    BORG_IDENTITY=${BORG_IDENTITY:-$(__mounted_volumes | xargs -n1 -I{} find {} -name 'id_*' | grep -v .pub | head -1 || true)}

    [[ -z "$BORG_IDENTITY" ]] \
    || export BORG_RSH="$BORG_RSH -o IdentityFile=$BORG_IDENTITY"

}

__borg_build_passphrase() {
    [[ -z "$BORG_PASSPHRASE" ]] \
    || return 0

    export BORG_PASSPHRASE="$(printenv | grep ^BORG_ | sort | cut -f2- -d= | xargs printf "%s" | base64 | sha256sum | awk '{print $1}' | cut -b-64)"
}

__borg_backup_source() {
    if [[ -n "$(__mounted_volumes -d | head -1)" ]]; then echo "$(__mounted_volumes -d | head -1)"; return 0; fi
    if [[ -d "/source" ]]; then echo /source; return 0; fi
    echo "/source"
}

__borg_build_archive() {
    [[ -n "$BORG_ARCHIVE_NAME" ]] \
    || export BORG_ARCHIVE_NAME="$( basename "$(__borg_backup_source)" )"

    [[ ! "$BORG_ARCHIVE_NAME" = "source" ]] \
    || export BORG_ARCHIVE_NAME="$(hostname -f)"

    [[ -n "$BORG_ARCHIVE_PATH" ]] \
    || export BORG_ARCHIVE_PATH="/backups"

    [[ -n "$BORG_SERVER" ]] \
    || export BORG_SERVER="$(ping -c1 backup >/dev/null 2>&1 && echo backup || true)"

    [[ -n "$BORG_SERVER" ]] \
    || export BORG_SERVER="$(ping -c1 borgbackup >/dev/null 2>&1 && echo borgbackup || true)"
    
    [[ -n "$BORG_SERVER" ]] \
    || export BORG_SERVER="localhost"

    [[ -n "$BORG_ARCHIVE" ]] \
    || export BORG_ARCHIVE="ssh://${BORG_USER:+$BORG_USER@}$BORG_SERVER${BORG_PORT:+:$BORG_PORT}/.$BORG_ARCHIVE_PATH/$BORG_ARCHIVE_NAME"
}

__borg_naming_pattern() {
    printf '%s' "${BORG_NAMING_PATTERN:-::{now:%Y-%m-%d_%H:%M}}"
}

__borg_compression() {
    printf '%s' "${BORG_COMPRESSION:---compression zstd,22}"
}

__borg_init() {
    exec borg init --encryption=repokey "$BORG_ARCHIVE"
}

__borg_create() {
    cd "$(__borg_backup_source)"
    exec borg create --stats $(__borg_compression) "$BORG_ARCHIVE$(__borg_naming_pattern)" .
}

__borg_prune() {
    true
}

__borg_extract() {
    true
}

# Enable call tracing
[[ -z "${TRACE:+x}" ]] || __debug

# load environment
__vars

# Initialize environment and inject tini for clean process handling
[[ -n "$(pidof tini)" ]] || __with_reaper "${@}"


case "$1" in
    init)
        __borg_init
    ;;
    backup|create)
        __borg_create
    ;;
    restore|prune|extract)
        echo "TBD"
    ;;
    *)
        __run_command "${@}"
    ;;
esac

cat <<'__EO_USAGE'
Usage:
docker run borgbackup (backup|restore|init|create|prune|extract)
docker run -ti borgbackup $command
__EO_USAGE
exit 1
