#!/usr/bin/env bash

#shamelessly adapted from https://github.com/AdrianKoshka/1339secure
# shellcheck disable=SC2034
__VOLACRYPTSH_VERSION__=1.2

if ! OPTS=$(getopt --alternative --options hr:n:p:u: \
    --longoptions help,room:,nick:,pass:,pp:,room-pass:,passphrase:,sp,skip-passphrase \
    -n 'vid2vola.sh' -- "$@"); then
    echo -e "\nFiled parsing options.\n" ; exit 1
fi

IFS=$'\r'

if [[ ! $(type gpg 2>/dev/null) ]]; then echo "Please install GPG"; exit; fi
if [[ ! $(type curl 2>/dev/null) ]]; then echo "Please install curl"; exit; fi
if [[ $(type curlbar 2>/dev/null) ]]; then
    cURL="curlbar"
else
    cURL="curl"
fi

if [[ -f "$HOME/.volascriptsrc" ]]; then
    #shellcheck disable=SC1090
    source "$HOME/.volascriptsrc"
fi

cleanup() {
    trap - SIGHUP SIGTERM SIGINT
    local failure
    local exit_code="$1"
    local file_to_remove="$2"
    if [[ "$exit_code" == "" ]]; then
        echo -e "\n\033[0mProgram interrupted by user."
        exit_code=10
    fi
    if [[ $file_to_remove != "none" ]] && [[ $file_to_remove != "" ]]; then
        rm -f "$file_to_remove"
    fi
    for failure in "${@:3}"; do
        echo -e "\033[31m$failure\033[0m" >&2
   done;  exit "$exit_code"
}

eval set -- "$OPTS"

while true; do
    case "$1" in
        -h | -help | --help) HELP="true" ; shift ;;
        -r | -room | --room ) ROOM="$2"; shift 2;;
        -n | -nick | --nick) NICK="$2" ; shift 2 ;;
        -p | -password | --password) PASSWORD="$2" ; shift 2 ;;
        -u | -room-pass | --room-pass) ROOMPASS="$2" ; shift 2 ;;
        -pp | --pp | --passphrase ) PASSPHRASE="$2"; shift 2;;
        -sp | --sp | --skip-passphrase ) SKIP="true"; shift ;;
        --) shift
            input_URI="$(echo "$1" | sed -r "s/%23/#/g")"
            in_file="$(basename "$input_URI"  | cut -d'#' -f1)"
            break ;;
        * ) shift ;;
    esac
done

print_help() {
cat >&2 << EOF
volacrypt.sh help page

    If run on a file, will encrypt the file and upload it to volafile.
    If run on a special volafile URL, it will download and decrypt.

-h, --help
    Show this help message.

-r, --room <room_name>
    Specifiy upload room. (This plus at least one upload target is the only
    required option to upload something).

-n, --nick <name>
    Specify name, under which your file(s) will be uploaded.

-p, --password <password>
    Set your account password. If you upload as logged user, file
    uploads will count towards your file stats on Volafile.
    See https://volafile.org/user/<your_username>

-pp, --pasphrase <passphrase>
    Specify the passphrase for data decryption. This option only works with
    downloading the file.

-sp, --skip-passphrse
    By specifying this option script won't append the passphrase to the filename
    of uploaded file.

EOF
exit 0

}

function encrypt_upload() {
    trap 'cleanup "" "$out_file"' SIGINT SIGTERM SIGHUP
    local pass; pass="$(< /dev/urandom tr -dc '[:alnum:]' | head -c22)"  # ~131bits entropy
    if [[ "$SKIP" == "true" ]]; then
        local out_file="/tmp/$in_file"
    else
        local out_file="/tmp/$in_file#$pass"
    fi
    if [[ ! -f "$input_URI" ]]; then
        cleanup "2" "none" "You need to specify a file in order for this to work!"
    fi
    printf "%s" "$pass" | gpg --output "$out_file" --batch --passphrase-fd 0 \
        --symmetric --cipher-algo AES256 "$input_URI" || \
        cleanup "3" "$out_file" "Error on the gpg side."
    if [[ -n "$NICK" ]]; then
        ARG_PREP="${ARG_PREP}-n$IFS$NICK$IFS"
    fi
    if [[ -n "$PASSWORD" ]]; then
        ARG_PREP="${ARG_PREP}-p$IFS$PASSWORD$IFS"
    fi
    if [[ -n "$ROOM" ]]; then
        ARG_PREP="${ARG_PREP}-r$IFS$ROOM$IFS"
    fi
    if [[ -n "$ROOMPASS" ]]; then
        ARG_PREP="${ARG_PREP}-u$IFS$ROOMPASS$IFS"
    fi
    ARG_PREP="$ARG_PREP$out_file"
    printf "%s" "$ARG_PREP" | xargs -d "$IFS" volaupload.sh || \
        cleanup "4" "$out_file" "Error on the volaupload side."
    if [[ "$SKIP" == "true" ]]; then
        echo "Send this passphrase to your peer so he can decrypt your file:" >&2
        echo "$pass"
    fi
    cleanup "0" "$out_file"
}

function download_decrypt() {
    trap 'cleanup "" "$encrypted_file"' SIGINT SIGTERM SIGHUP
    local encrypted_file
    local pass
    local error
    encrypted_file="$(mktemp)"
    $cURL -fLH "Cookie: allow-download=1" "$input_URI" --output "$encrypted_file"
    error="$?"
    if [[ ! "$error" -eq 0 ]] && [[ ! "$error" -eq 102 ]]; then
        cleanup "5" "$encrypted_file" "Couldn't download your stuff."
    else
        echo -e "\nDownload complete. Decrypting...\n" >&2
    fi
    if [[ -n "$PASSPHRASE" ]]; then
        pass="$PASSPHRASE"
    else
        pass="$(echo "$input_URI" | cut -d'#' -f2)"
    fi
    printf "%s" "$pass" | gpg --output "$in_file" --batch --passphrase-fd 0 \
        --decrypt "$encrypted_file" || \
        cleanup "3" "$encrypted_file" "Error on the gpg side."
    echo -e "\nAll done!" >&2
    cleanup "0" "$encrypted_file"
}

if [[ -n $HELP ]]; then
    print_help
elif [[ -n "$PASSPHRASE" ]] && [[ -n "$SKIP" ]]; then
    cleanup "6" "none" "Can't encrypt and decrypt at the same time.\n"
elif [[ "$input_URI" == "https://volafile.org"* ]]; then
    download_decrypt
else
    if [[ ! -f "$input_URI" ]]; then
        cleanup "7" "none" "Can't encrypt something that doesn't exist!\n"
    fi
    encrypt_upload
fi
