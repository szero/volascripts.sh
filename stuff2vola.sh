#!/usr/bin/env bash
# shellcheck disable=SC2155,SC1117

# shellcheck disable=SC2034
__STUFF2VOLASH_VERSION__=2.3

if ! OPTS=$(getopt --options hr:n:p:u:a:f:d:ob \
    --longoptions help,room:,nick:,pass:,room-pass:,upload-as:,force-server:,dir:,audio-only,best-quality \
    -n 'stuff2vola.sh' -- "$@"); then
    echo -e "\nFailed while parsing options.\n"; exit 1
fi

if [[ -f "$HOME/.volascriptsrc" ]]; then
    #shellcheck disable=SC1090
    source "$HOME/.volascriptsrc"
fi

IFS=$'\r'

if [ -z "$TMPDIR" ]; then
    TMP="/tmp"
else
    TMP="${TMPDIR%/}"
fi

cleanup() {
    for d in $DIR_LIST ; do
        rm -rf "$d"
    done
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

print_help() {
cat >&2 << EOF

stuff2vola.sh help page

    Download stuff from the web and than upload it to volafile.
    Every argument that is not prepended with any
    option will be treated as upload-after-download target.

-h, --help
    Show this help message.

-r, --room <room_name>
    Specifiy upload room. (This plus at least one upload target is the only
    required option to upload something).

-n, --nick <name>
    Specify name, under which your file(s) will be uploaded.

-p, -pass <password>
    Set your account password. If you upload as logged user, file
    uploads will count towards your file stats on Volafile.
    See https://volafile.org/user/<your_username>

-u, --room-pass <password>
    You need to specify this only for password protected rooms.

-a, --upload-as <renamed_file>
    Upload file with custom name.

-f, --force-server <server_number>
   Force uploading to a specific server because not all of them are equal.

-d, --dir <destination_directory>
    If you will specify this option, all of your downloaded files will be
    saved into the given directory.

-o, --audio-only
    If file you want forward to Volafile is a video, this option will strip
    video stream from it and upload only audio stream.

-b, --best-quality
    Script downloads videos in 720p resolution and lossy audio files like
    opus or mp3 by default. Set this option to download highest quality
    video and audio files.

EOF
exit 0
}

eval set -- "$OPTS"

while true; do
    case "$1" in
        -h | --help) print_help ; shift ;;
        -r | --room ) ROOM="$2"; shift 2 ;;
        -n | --nick) NICK="$2" ; shift 2 ;;
        -p | --pass) PASSWORD="$2" ; shift 2 ;;
        -u | --room-pass) ROOMPASS="$2"; shift 2 ;;
        -a | --upload-as) ASS+=("$2"); shift 2 ;;
        -f | --force-server) UL_SERVER="$2"; shift 2 ;;
        -d | --dir) VID_DIR="$2"
                if [[ ! -d "$VID_DIR" ]]; then
                    cleanup "4" "\nYou specified invalid directory.\n"
                fi
                if [[ "$VID_DIR" == "." ]]; then
                   VID_DIR="$PWD"
                fi; shift 2 ;;
        -o | --audio-only) A_ONLY="true"; shift ;;
        -b | --best-quality) BEST_Q="true"; shift ;;
        --) shift;
            until [[ -z "$1" ]]; do
                LINKS+=("$1") ; shift
            done ; break ;;
        * ) shift ;;
    esac
done

if [[ -z "$(command -v curlbar)" ]]; then
    cURL="curl"
else
    cURL="curlbar"
fi

skip() {
    printf "\033[31m" >&2
    case $1 in
        0 | 102)
            if [[ $1 -eq 102 ]]; then
                printf "\033[33mFile was too small to make me bothered with printing the progress bar.\033[0m\n\n" >&2
            fi ; return 0 ;;
        22) echo -e "$2: No such file on the interwebs.\033[0m\n" >&2; return 1 ;;
        3 | 6 ) echo -e "$2: This link is busted or its not a link at all."
            echo -e "Try with a valid one.\033[0m\n" >&2; return 1 ;;
        * ) echo -e "cURL error of code $1 happend.\033[0m\n" >&2; return 1 ;;
    esac
}

getContentType(){
    local status="$1/status-file"
    local FIFO="$1/content-type"
    local curl_pid
    mkfifo "$FIFO"

    ( set +e
    curl -fsLIX GET -H "Cookie: allow-download=1" "$2" >> "$FIFO"
    echo "$?" >> "$status"
    echo >> "$FIFO"
    sync
    ) &
    curl_pid="$!"

    sed -nu \
        -e "y/CEHNOPTY/cehnopty/" \
        -e "/^http\/1.0/p" \
        -e "/^http\/1/p" \
        -e "/^http\/1.1/p" \
        -e "/^http\/2/p" \
        -e "/^content-type:/p" \
        "$FIFO" | \
    {
    trap cleanup SIGINT
    local lastredirect=1
    local filetype
    while local IFS=' '; read -r -a line; do
        if [[ "${line[1]}" == "200" ]]; then
            lastredirect=0
        fi
        if [[ $lastredirect -eq 0 ]] && [[ "${line[0]}" == "content-type:" ]]; then
            filetype=$(echo "${line[1]%%;*}" | tr -d '[:space:]')
        fi
    done
    sync
    rm -f "$FIFO"
    kill -9 "$curl_pid" 2>/dev/null || true
    echo -n "$filetype"
    }
    return "$(cat "$status")"
}

#thanks stackoverflow! https://stackoverflow.com/a/37840948
urldecode() { : "${*//+/ }"; echo -e "${_//%/\\x}"; }

youtube-dlBar() {
# shellcheck disable=SC2068
youtube-dl --newline $@ 2>&1 | \
    sed -nu \
    -e '/^\[download\]/p' \
    -e '/^WARNING:/p' \
    -e '/^ERROR:/p' \
    -e '/^\[ffmpeg\]/p'| \
{
local re='[0-9\.%~]{1,4}'
local SLEEP_PID=-1
local speed
local eta
local IFS=$' '
while  read -r -a line; do
    if [[ "${line[1]}" == "100%" ]]; then
        printf "\x1B[0G %-5s\x1B[7m%*s\x1B[27m%*s of %9s at %9s %8s ETA\x1B[0K\x1B[${curpos}G\n\n" \
        "${percent%%.*}%" "$on" "" "$off" "" "${line[3]//[~]}" "$speed" "$eta" >&2
    elif [[ ${line[0]} == "[download]" ]] && [[ "${line[1]}" =~ $re ]]; then
        speed="${line[5]}"
        eta="${line[7]}"
        local percent="${line[1]//%}"
        local width=$(( $(tput cols) - 50 ))
        local curpos=$((width + 6))
        local filesize="${line[3]//[a-zA-Z~]}"
        local bytes=$( bc <<< "scale=2; ${line[1]%*%} * $filesize / 100" )
        local on=$( bc <<< "$bytes * $width / $filesize" )
        local off=$( bc <<< "$width - $on" )
        if [[ -z "$(ps -hq "$SLEEP_PID" 2>/dev/null)" ]]; then
            sleep 1 &
            SLEEP_PID="$!"
            printf "\x1B[0G %-5s\x1B[7m%*s\x1B[27m%*s of %9s at %9s %8s ETA\x1B[0K\x1B[${curpos}G" \
            "${percent%%.*}%" "$on" "" "$off" "" "${line[3]//[~]}" "$speed" "$eta" >&2
        fi
    elif  [[ ${line[1]} == "Downloading" ]]; then
        echo >&2; echo -ne "${line[*]:1}" >&2 | tr -d "\n\r" >&2; echo >&2
    elif [[ ${line[0]} == "WARNING:" ]]; then
        continue
    elif [[ ${line[0]} == "ERROR:" ]]; then
        echo -ne "\033[31m${line[*]:1}. Skipping...\033[33m\n" >&2
    elif [[ ${line[1]} == "Destination:" ]]; then
        echo -ne "${line[*]:1}" >&2 | tr -d "\n\r" >&2; printf "\n" >&2;
    else
        echo -ne "${line[*]:1}" >&2 | tr -d "\n\r" >&2; printf "\n\n" >&2;
    fi
done
return 0
}
}

postStuff() {
    if [[ $A_ONLY == "true" ]]; then
        local args=$'-ixf\nbestaudio/wav/opus/mp3/m4a/ogg'
    else
        if [[ $BEST_Q == "true" ]]; then
            local args=$'-if\nbestvideo[ext=mp4]+bestaudio[ext=m4a]/mp4/webm/bestaudio'
        else
            local args=$'-if\nbestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/mp4/webm/opus/mp3/ogg'
        fi
    fi
    local dir
    local ftype
    local error
    local file
    local raw
    local filepath

    set -- "${ASS[@]}"
    for l in "${LINKS[@]}" ; do
        dir="$TMP/volastuff_$(head -c6 <(tr -dc '[:alnum:]' < /dev/urandom))"
        DIR_LIST="${DIR_LIST}${dir}$IFS"
        mkdir -p "$dir"
        ftype="$(getContentType "$dir" "$l")"
        error="$?"
        skip "$error" "$l" || continue
        filepath="$(urldecode "$dir/$(basename "$l")")"
        echo -e "\033[32m<\033[38;5;88m\\/\033[32m> Downloading from \033[1m$l\033[22m \033[33m"
        if [[ "$ftype" == "text/html" ]]; then
            youtube-dlBar "-o" "$dir/%(title)s.%(ext)s" "$args" "$l"
        else
            if [[ "$l" =~ ^.*volafile\.[net|org|io] ]]; then
                echo -e "Destination: $filepath"
                if [[ -n "$NICK" ]] && [[ -n "$PASSWORD" ]]; then
                    local cookie err
                    cookie="$(volaupload.sh -c login "name=$NICK&password=$PASSWORD")"; err="$?"
                    if [[ $err -eq 10 ]]; then
                        cookie="$(echo -ne "$cookie" | cut -d$'\n' -f1)"
                        $cURL -1fLH "Cookie: allow-download=1" -H "Cookie: $cookie" "$l" > "$filepath"
                    else
                        cleanup "3" "Error on the volaupload.sh side.\n"
                    fi
                else
                    $cURL -1fLH "Cookie: allow-download=1" "$l" > "$filepath"
                fi
            else
                echo -e "Destination: $filepath"
                $cURL -L "$l" > "$filepath"
            fi
            echo >&2
        fi
        error="$?"
        skip "$error" "$l" || continue
        raw=$(find "$dir" -maxdepth 1 -regextype posix-egrep -regex ".+\.[a-zA-Z0-9\%\?=&_-]+$" \
            -printf "%A@ %f\n" | sort -rk1n | cut -d' ' -f2-)
        file="$(echo "$raw" | sed -r "s/^(.*\.[0-9a-zA-Z]{1,7}).*/\1/")"
        if [[ -z "$file" ]]; then
            file="$raw"
        else
            mv -f "$dir/$raw" "$dir/$file" 2>/dev/null
        fi
        IFS=$'\n'
        local CR=$'\r'
        for f in $file ; do
            if [[ -n "$1" ]] && [[ -d "$VID_DIR" ]]; then
                mv -f "${dir}/${f}" "${dir}/$1.${f##*.}" 2>/dev/null
                cp -n "${dir}/$1.${f##*.}" "$VID_DIR"
                ARG_PREP="${ARG_PREP}${dir}/$1.${f##*.}$CR"; shift
            elif [[ -d "$VID_DIR" ]]; then
                cp -n "${dir}/${f}" "$VID_DIR"
                ARG_PREP="${ARG_PREP}${dir}/${f}$CR"
            elif [[ -n "$1" ]]; then
                ARG_PREP="${ARG_PREP}-a$CR${1}$CR${dir}/${f}$CR"; shift
            else
                ARG_PREP="${ARG_PREP}${dir}/${f}$CR"
            fi
        done
        IFS=$'\r'
    done
    if [[ -z ${ARG_PREP} ]]; then
        cleanup "2" "None of your links were valid. Closing the party.\n"
    fi
    local current; current="$(date "+%s")"
    echo -en "\033[0mDownloading completed in "
    TZ='' date -d "@$((current-download_start))" "+%H hours, %M minutes and %S seconds.%n"
    #if [[ -n "$NICK" ]]; then
        ARG_PREP="${ARG_PREP}-n$IFS$NICK$IFS"
    #fi
    #if [[ -n "$PASSWORD" ]]; then
        ARG_PREP="${ARG_PREP}-p$IFS$PASSWORD$IFS"
    #fi
    if [[ -n "$ROOMPASS" ]]; then
        ARG_PREP="${ARG_PREP}-u$IFS$ROOMPASS$IFS"
    fi
    if [[ -n "$ROOM" ]]; then
        ARG_PREP="${ARG_PREP}-r$IFS$ROOM$IFS"
    fi
    if [[ -n "$UL_SERVER" ]]; then
        ARG_PREP="${ARG_PREP}-f$IFS$UL_SERVER$IFS"
    fi
    printf "%s" "$ARG_PREP" | xargs -d "$IFS" volaupload.sh \
          || cleanup "3" "Error on the volaupload.sh side.\n"
}

trap cleanup SIGINT
trap 'cleanup "1"' SIGHUP SIGTERM
trap 'cleanup "0"' EXIT

if [[ "${#LINKS[@]}" -eq 0 ]]; then
    cleanup "1" "My dude, comon. You tried to download nothing.\n"
else
    download_start="$(date "+%s")"
    postStuff
fi
