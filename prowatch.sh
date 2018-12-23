#!/usr/bin/env bash
# shellcheck disable=SC1117

# shellcheck disable=SC2034
__PROWATCHSH_VERSION__=1.2

if ! OPTS=$(getopt --alternative --options hn:p: \
    --longoptions help,nick:,pass: \
    -n 'prowatch.sh' -- "$@"); then
    echo -e "\nFailed while parsing options.\n" ; exit 1
fi

IFS=$'\r'

if [[ -f "$HOME/.volascriptsrc" ]]; then
    #shellcheck disable=SC1090
    source "$HOME/.volascriptsrc"
fi

handle_exit() {
    trap - SIGHUP SIGTERM SIGINT EXIT
    local failure
    local exit_code="$1"
    if [[ "$exit_code" == "" ]]; then
        echo -e "\n\033[0mProgram interrupted by user."
        exit_code=10
    fi
    for failure in "${@:2}"; do
        echo -e "\033[31m$failure\033[0m" >&2
   done; exit "$exit_code"
}

warn() {
    local omit
    for omit in "$@"; do
        echo -e "\033[33m$omit\033[0m" >&2
    done
}

print_help() {
cat >&2 << EOF

prowatch.sh help page

    Watch and listen to stuff that is currently uploaded to Volafile with
    Volfile Pro™ speeds.
    Every argument that is not prepended with any option will be treated as
    link to media hosted on vola. You can still use this script as non-pro
    user but you will get usual download speeds which may result in longer
    buffering.

-h, --help
    Show this help message.

-n, --nick <name>
    Specify your login name.

-p, --pass <password>
    Set your password.

EOF
exit 0
}

eval set -- "$OPTS"

while true; do
    case "$1" in
        -h | -help | --help) print_help ; shift ;;
        -n | -nick | --nick) NICK="$2" ; shift 2 ;;
        -p | -password | --password) PASSWORD="$2" ; shift 2 ;;
        --) shift;
            until [[ -z "$1" ]]; do
                LINKS+=("$1") ; shift
            done ; break ;;
        * ) shift ;;
    esac
done

trap 'handle_exit "0"' EXIT
trap 'handle_exit "1"' SIGHUP SIGTERM
trap handle_exit SIGINT

declare -i argc
argc=${#LINKS[@]}

if [[ $argc -eq 0 ]]; then
    handle_exit "2" "You didn't specify any files that can be streamed!\n"
elif [[ -z "$NICK" ]] || [[ -z "$PASSWORD" ]]; then
    warn "No nick and/or password supplied." \
        "Video will be buffered with regular Vola speeds."
fi
cookie="Cookie: allow-download=1"
session="$(volaupload.sh -c login "name=$NICK&password=$PASSWORD")"; err="$?"
session="$(echo -ne "$session" | cut -d$'\n' -f1)"
if [[ "$(echo -ne "$session" | cut -d'=' -f1)" != "error.code" ]]; then
    cookie+="; $session"
fi
if [[ $err -eq 10 ]]; then
    for l in "${LINKS[@]}"; do
        if [[ $(type mpv 2>/dev/null) ]]; then
            mpv "$l" --no-ytdl --cookies --http-header-fields="$cookie"
        elif [[ $(type vlc 2>/dev/null) ]]; then
            curl -1sfLH "$cookie" "$l" -o - | vlc -
        else
            handle_exit "3" "Install mpv or vlc if you want to use this script!" \
                "Type 'prowatch.sh --help' for more info."
        fi
    done
    handle_exit "0"
fi
handle_exit "4" "cURL error of code $err happened"
