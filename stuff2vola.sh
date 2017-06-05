#!/usr/bin/env bash
# shellcheck disable=SC2155,SC2162,SC2164,SC2103

# shellcheck disable=SC2034
__STUFF2VOLASH_VERSION__=1.1

if ! OPTS=$(getopt --options hl:r:n:p:a:d:og \
    --longoptions help,link:,room:,nick:,password:,upload-as:,dir:,audio-only,purge \
    -n 'vid2vola.sh' -- "$@"); then
    echo -e "\nFiled parsing options.\n" ; exit 1
fi

############################################################################################
# If you wish to preserve downloaded files, you can add `export VID_DIR="/path/to/dir"`    #
# line to your shell config (usually located in ~/.bashrc)                                 #
############################################################################################


IFS=$'\r'
if [ -z "$TMPDIR" ]; then
    TMP="/tmp"
else
    TMP="${TMPDIR%/}"
fi

eval set -- "$OPTS"

cleanup() {
    cd "$TMP"
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

while true; do
    case "$1" in
        -h | --help) HELP="true" ; shift ;;
        -l | --link ) LINKS="${LINKS}${2}$IFS"; shift 2;;
        -r | --room ) ROOM="$2"; shift 2;;
        -n | --nick) NICK="$2" ; shift 2 ;;
        -p | --password) PASSWORD="$2" ; shift 2 ;;
        -a | --upload-as) ASS="${ASS}${2}$IFS"; shift 2;;
        -d | --dir) VID_DIR="$2"
                if [[ ! -d "$VID_DIR" ]]; then
                    cleanup "4" "You specified invalid directory.\n"
                fi; shift 2;;
        -o | --audio-only) A_ONLY="true"; shift ;;
        -g | --purge) PURGE="true"; shift ;;
        --) shift;
            until [[ -z "$1" ]]; do
                LINKS="${LINKS}${1}$IFS" ; shift
            done ; break ;;
        * ) shift ;;
    esac
done


print_help() {
    echo -e "\nstuff2vola.sh help page\n"
    echo -e "-h, --help"
    echo -e "   Show this help message.\n"
    echo -e "-l, --link <upload_target>"
    echo -e "   Download and the upload stuff from the web. Every argument that is not prepended"
    echo -e "   with suitable option will be treated as upload target.\n"
    echo -e "-r, --room <room_name>"
    echo -e "   Specifiy upload room. (This plus at least one upload target is the only"
    echo -e "   required option to upload something).\n"
    echo -e "-n, --nick <name>"
    echo -e "   Specify name, under which your file(s) will be uploaded.\n"
    echo -e "-p, -pass <password>"
    echo -e "   Set your account password. If you upload as logged user, file"
    echo -e "   uploads will count towards your file stats on Volafile."
    echo -e "   See https://volafile.org/user/<your_username>\n"
    echo -e "-a, --upload-as <renamed_file>"
    echo -e "   Upload file with custom name.\n"
    echo -e "-d, --dir <destination_directory>"
    echo -e "   If you will specify this option, all of your downloaded files will be saved"
    echo -e "   into the given directory.\n"
    echo -e "-o, --audio-only"
    echo -e "   If file you want forward to Volafile is a video, this option will strip video"
    echo -e "   stream from it and upload only audio stream.\n"
    echo -e "-g, --purge"
    echo -e "   Set this if you don't want to keep any downloaded files.\n"
    exit 0
}

if [[ -z "$(which curlbar)" ]]; then
    cURL="curl"
else
    cURL="curlbar"
fi

ask_keep() {
    echo -e "Do you want to keep \033[1m$(basename "$1")\033[22m?"
    while true; do
        local yn; printf "\033[32m[Y]es\033[0m/\033[31m[N]o\033[0m) "; read -e yn
        case "$yn" in
            [Yy]*) local path2stuff;
                while true; do
                    printf "\033[32mDirectory name:\033[0m "; read -e path2stuff
                    path2stuff="${path2stuff/#\~/$HOME}"
                    if [[ -d "$path2stuff" ]]; then
                        mv -f "$1" "$path2stuff" ; return
                    else
                        echo "You didn't specify a valid directory!"; continue
                    fi
                done ;;
            [Nn]*) break ;;
            * )  continue ;;
        esac
    done
}

skip() {
    printf "\033[31m" >&2
    case $1 in
        0 ) printf "\033[0m" >&2; return 0 ;;
        6 ) echo -e "\n$2: This link is busted. Try with a valid one.\033[0m" >&2; return 1;;
        * ) echo -e "\ncURL error of code $1 happend.\033[0m" >&2; return 1 ;;
    esac
}


getContentType(){
    local FIFO="content-type"
    local status="status-file"
    local curl_pid
    mkfifo "$FIFO"

    ( set +e
    curl -sLI "$1" >> "$FIFO"
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
            filetype=$(echo "${line[1]}" | tr -d ';[:space:]')
        fi
    done
    sync
    rm -f "$FIFO"
    kill -9 "$curl_pid" 2>/dev/null || true
    echo -n "$filetype"
    }
    return "$(cat $status)"
}

youtube-dlBar() {
youtube-dl --newline -o "%(title)s.%(ext)s" -f "$1" "$2" 2>&1 | \
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
    elif [[ "${line[1]}" =~ $re ]]; then
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
    elif [[ ${line[0]} == "ERROR:" ]]; then
        # shellcheck disable=SC2145
        echo -e "\n\033[31m${line[@]:1}. Closing script.\033[0m\n" >&2; return 1
    else
        echo -e "${line[@]:1}"
    fi
done
return 0
}
}

postStuff() {
    if [[ $A_ONLY == "true" ]]; then
        local arg="wav/mp3/m4a/ogg"
    else
        local arg="bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/mp4/webm/wav/mp3/m4a/ogg"
    fi
    local dir
    local ftype
    local error
    local file

    cd "$TMP"
    for l in $LINKS ; do
        dir="tmp_$(head -c10 < <(tr -dc '[:alnum:]' < /dev/urandom))"
        DIR_LIST="${DIR_LIST}${dir}$IFS"
        mkdir -p "$dir"
        cd "$dir"
        ftype="$(getContentType "$l")"
        error="$?"
        skip "$error" "$l" || continue
        echo -e "\033[32m<v> Downloading to \033[1m$TMP/$dir\033[22m"
        printf "\033[33m"
        if [[ "$ftype" == "text/html" ]]; then
            youtube-dlBar "$arg" "$l"
        else
            $cURL -L "$l" > "$(basename "$l")" ; echo >&2
        fi
        error="$?"
        printf "\033[0\n"
        skip "$error" "$l" || continue
        file=$(find -maxdepth 1 -regextype posix-egrep -regex ".+\.[a-zA-Z0-9?]{2,20}" -printf "%f")
        if [[ -n "$file" ]]; then
            FILE_LIST="${FILE_LIST}${dir}/${file}$IFS"
        fi
        cd ..
    done
    if [[ ${#FILE_LIST} -eq 0 ]]; then
        cleanup "2" "Any of your links weren't valid. Closing the party.\n"
    fi
    #shellcheck disable=SC2086
    set -- $ASS
    for f in $FILE_LIST ; do
        if [[ -n "$1" ]]; then
            ARG_PREP="${ARG_PREP}-a$IFS${1}$IFS${f}$IFS" ; shift
        else
            ARG_PREP="${ARG_PREP}${f}$IFS"
        fi

    done
    printf "%s" "$ARG_PREP" | xargs -d "$IFS" volaupload.sh \
        -r "$ROOM" -n "$NICK" -p "$PASSWORD"  || cleanup "3" "Error on the volaupload.sh side.\n"
    if [[ -n "$PURGE" ]]; then
        cleanup "0"
    else
        if [[ -d "$VID_DIR" ]] ; then
            for f in $FILE_LIST ; do
                mv -f "$f" "$VID_DIR"
            done
        else
            for f in $FILE_LIST ; do
                ask_keep "$f"
            done
        fi
        cleanup "0"
    fi
}

trap cleanup SIGHUP SIGTERM SIGINT

if [[ -n $HELP ]]; then
    print_help
elif [[ -z "$LINKS" ]]; then
    cleanup "1" "My dude, comon. You tried to download nothing.\n"
else
    postStuff
fi
