#!/usr/bin/env bash
# shellcheck disable=SC2155

# shellcheck disable=SC2034
__STUFF2VOLASH_VERSION__=1.5

if ! OPTS=$(getopt --options hr:n:p:a:d:ob \
    --longoptions help,room:,nick:,password:,upload-as:,dir:,audio-only,best-quality \
    -n 'vid2vola.sh' -- "$@"); then
    echo -e "\nFiled parsing options.\n" ; exit 1
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
    trap - SIGHUP SIGTERM SIGINT
    local failure
    local exit_code="$1"
    if [[ "$exit_code" == "" ]]; then
        echo -e "\n\033[0mProgram interrupted by user."
        exit_code=10
    fi
    for failure in "${@:2}"; do
        echo -e "\033[31m$failure\033[0m" >&2
    done;  exit "$exit_code"
}

eval set -- "$OPTS"

while true; do
    case "$1" in
        -h | --help) HELP="true" ; shift ;;
        -r | --room ) ROOM="$2"; shift 2;;
        -n | --nick) NICK="$2" ; shift 2 ;;
        -p | --password) PASSWORD="$2" ; shift 2 ;;
        -a | --upload-as) ASS+=("$2"); shift 2;;
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

-a, --upload-as <renamed_file>
    Upload file with custom name.

-d, --dir <destination_directory>
    If you will specify this option, all of your downloaded files will be saved
    into the given directory.

-o, --audio-only
    If file you want forward to Volafile is a video, this option will strip video
    stream from it and upload only audio stream.

-b, --best-quality
    Script downloads videos in 720p resolution and lossy audio files like opus or mp3 by
    default. Set this option to download highest quality video and audio files.

EOF
exit 0

}

if [[ -z "$(which curlbar)" ]]; then
    cURL="curl"
else
    cURL="curlbar"
fi

skip() {
    printf "\033[31m" >&2
    case $1 in
        0 | 102 ) printf "\033[0m" >&2; return 0 ;;
        22) echo -e "\n$2: No such file on the interwebs.\033[0m\n" >&2; return 1 ;;
        6 ) echo -e "\n$2: This link is busted or its not a link at all. Try with a valid one.\033[0m\n" >&2; return 1;;
        * ) echo -e "\ncURL error of code $1 happend.\033[0m\n" >&2; return 1 ;;
    esac
}

getContentType(){
    local FIFO="$1/content-type"
    local status="$1/status-file"
    local curl_pid
    mkfifo "$FIFO"

    ( set +e
    curl -fsLI "$2" >> "$FIFO"
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
local IFS=' '
while  read -r -a line; do
    if [[ "${line[1]}" == "100%" ]]; then
        printf "\x1B[0G %-5s\x1B[7m%*s\x1B[27m%*s of %9s at %9s %8s ETA\x1B[0K\x1B[${curpos}G\n\n" \
        "${percent%%.*}%" "$on" "" "$off" "" "${line[3]//[~]}" "$speed" "$eta"
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
        if [[ -z "$(ps -hp "$SLEEP_PID" 2>/dev/null)" ]]; then
            sleep 1 &
            SLEEP_PID="$!"
            printf "\x1B[0G %-5s\x1B[7m%*s\x1B[27m%*s of %9s at %9s %8s ETA\x1B[0K\x1B[${curpos}G" \
            "${percent%%.*}%" "$on" "" "$off" "" "${line[3]//[~]}" "$speed" "$eta" >&2
        fi
    elif [[ ${line[1]} == "Requested" ]]; then
        echo -e "Video and audio streams will be downloaded separately and merged together." >&2
    elif  [[ ${line[1]} == "Downloading" ]]; then
        echo -e "\n${line[*]:1}\n" >&2
    elif [[ ${line[0]} == "ERROR:" ]]; then
        echo -e "\033[31m${line[*]:1}. Skipping.\033[33m\n" >&2
    else
        echo -e "${line[*]:1}" >&2
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
    local f

    for l in "${LINKS[@]}" ; do
        dir="$TMP/volastuff_$(head -c4 <(tr -dc '[:alnum:]' < /dev/urandom))"
        DIR_LIST="${DIR_LIST}${dir}$IFS"
        mkdir -p "$dir"
        ftype="$(getContentType "$dir" "$l")"
        error="$?"
        skip "$error" "$l" || continue
        echo -e "\033[32m<\\/> Downloading \033[1m$l\033[22m \033[33m"
        if [[ "$ftype" == "text/html" ]]; then
            youtube-dlBar "-o" "$dir/%(title)s.%(ext)s" "$args" "$l"
        else
            echo "Destination: $dir/$(basename "$l")"
            $cURL -L "$l" > "$dir/$(basename "$l")"
        fi
        error="$?"
        printf "\033[0m\n"
        skip "$error" "$l" || continue
        IFS=$'\n'
        raw=$(find "$dir" -maxdepth 1 -regextype posix-egrep -regex ".+\.[a-zA-Z0-9\%\?=&_-]+$" \
            -printf "%f$IFS" | sort -n)
        file="$(echo "$raw" | sed -r "s/^(.*\.[0-9a-zA-Z]{1,4}).*/\1/")"
        if [[ -z "$file" ]]; then
            file="$raw"
        else
            mv -f "$dir/$raw" "$dir/$file" 2>/dev/null
        fi
        for f in $file ; do
            FILE_LIST+=("${dir}/${f}")
        done
        IFS=$'\r'
    done
    if [[ ${#FILE_LIST} -eq 0 ]]; then
        cleanup "2" "Any of your links weren't valid. Closing the party.\n"
    fi
    #shellcheck disable=SC2086
    set -- "${ASS[@]}"
    for f in "${FILE_LIST[@]}" ; do
        if [[ -n "$1" ]]; then
            ARG_PREP="${ARG_PREP}-a$IFS${1}$IFS${f}$IFS" ; shift
        else
            ARG_PREP="${ARG_PREP}${f}$IFS"
        fi

    done
    if [[ -n "$NICK" ]]; then
        ARG_PREP="${ARG_PREP}-n$IFS$NICK$IFS"
    fi
    if [[ -n "$PASSWORD" ]]; then
        ARG_PREP="${ARG_PREP}-p$IFS$PASSWORD$IFS"
    fi
    if [[ -n "$ROOM" ]]; then
        ARG_PREP="${ARG_PREP}-r$IFS$ROOM$IFS"
    fi
    printf "%s" "$ARG_PREP" | xargs -d "$IFS" volaupload.sh \
          || cleanup "3" "Error on the volaupload.sh side.\n"
    if [[ -d "$VID_DIR" ]] ; then
        for f in "${FILE_LIST[@]}" ; do
            mv -f "$f" "$VID_DIR"
        done
    fi
    cleanup "0"
}

trap cleanup SIGHUP SIGTERM SIGINT

if [[ -n $HELP ]]; then
    print_help
elif [[ "${#LINKS[@]}" -eq 0 ]]; then
    cleanup "1" "My dude, comon. You tried to download nothing.\n"
else
    postStuff
fi
