#!/bin/sh

main() {
	update_system
}

update_system() {
	asroot apt update
	apt list --upgradable
	asroot apt full-upgrade
}

install() {
    if [ "$(get_current_release)" ]; then
        log_info "Already installed"
        return
    fi
    if type=$(install_type); then
        log_info "Installing NextDNS..."
        log_debug "Using $type install type"
        if "install_$type"; then
            if [ ! -x "$NEXTDNS_BIN" ]; then
                log_error "Installation failed: binary not installed in $NEXTDNS_BIN"
                return 1
            fi
            configure
            post_install
            exit 0
        fi
    else
        return $?
    fi
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        printf "\033[30;1mDEBUG: %s\033[0m\n" "$*" >&2
    fi
}

log_info() {
    printf "INFO: %s\n" "$*" >&2
}

log_error() {
    printf "\033[31mERROR: %s\033[0m\n" "$*" >&2
}

print() {
    format=$1
    if [ $# -gt 0 ]; then
        shift
    fi
    # shellcheck disable=SC2059
    printf "$format" "$@" >&2
}

println() {
    format=$1
    if [ $# -gt 0 ]; then
        shift
    fi
    # shellcheck disable=SC2059
    printf "$format\n" "$@" >&2
}

doc() {
    # shellcheck disable=SC2059
    printf "\033[30;1m%s\033[0m\n" "$*" >&2
}

menu() {
    while true; do
        n=0
        default=
        for item in "$@"; do
            case $((n%3)) in
            0)
                key=$item
                if [ -z "$default" ]; then
                    default=$key
                fi
                ;;
            1)
                echo "$key) $item"
                ;;
            esac
            n=$((n+1))
        done
        print "Choice (default=%s): " "$default"
        read -r choice
        if [ -z "$choice" ]; then
            choice=$default
        fi
        n=0
        for item in "$@"; do
            case $((n%3)) in
            0)
                key=$item
                ;;
            2)
                if [ "$key" = "$choice" ]; then
                    if ! "$item"; then
                        log_error "$item: exit $?"
                    fi
                    break 2
                fi
                ;;
            esac
            n=$((n+1))
        done
        echo "Invalid choice"
    done
}

ask_bool() {
    msg=$1
    default=$2
    case $default in
    true)
        msg="$msg [Y|n]: "
        ;;
    false)
        msg="$msg [y|N]: "
        ;;
    *)
        msg="$msg (y/n): "
    esac
    while true; do
        print "%s" "$msg"
        read -r answer
        if [ -z "$answer" ]; then
            answer=$default
        fi
        case $answer in
        y|Y|yes|YES|true)
            echo "true"
            return 0
            ;;
        n|N|no|NO|false)
            echo "false"
            return 0
            ;;
        *)
            echo "Invalid input, use yes or no"
            ;;
        esac
    done
}

asroot() {
    # Some platform (merlin) do not have the "id" command and $USER report a non root username with uid 0.
    if [ "$(grep '^Uid:' /proc/$$/status 2>/dev/null|cut -f2)" = "0" ] || [ "$USER" = "root" ] || [ "$(id -u 2>/dev/null)" = "0" ]; then
        "$@"
    elif [ "$(command -v sudo 2>/dev/null)" ]; then
        sudo "$@"
    else
        echo "Root required"
        su -m root -c "$*"
    fi
}

silent_exec() {
    if [ "$DEBUG" = 1 ]; then
        "$@"
    else
        if ! out=$("$@" 2>&1); then
            rt=$?
            println "\033[30;1m%s\033[0m" "$out"
            return $rt
        fi
    fi
}

umask 0022
main