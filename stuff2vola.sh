#!/usr/bin/env bash
# shellcheck disable=SC2155,SC2145

if ! OPTS=$(getopt --options hl:r:n:p:a:d:o \
    --longoptions help,link:,room:,nick:,password:,upload-as:,dir:,audio-only \
    -n 'vid2vola.sh' -- "$@"); then
    echo -e "\nFiled parsing options.\n" ; exit 1
fi

############################################################################################
# If you wish to preserve downloaded files, you can add `export VID_DIR="/path/to/dir"`    #
# line to your shell config (usually located in ~/.bashrc)                                 #
############################################################################################


IFS="$(printf '\r')"

eval set -- "$OPTS"

while true; do
    case "$1" in
        -h | --help) HELP="true" ; shift ;;
        -l | --link ) LINKS="${LINKS}${2}$IFS"; shift 2;;
        -r | --room ) ROOM="$2"; shift 2;;
        -n | --nick) NICK="$2" ; shift 2 ;;
        -p | --password) PASSWORD="$2" ; shift 2 ;;
        -a | --upload-as) ASS="${ASS}${2}$IFS"; shift 2;;
        -d | --dir) VID_DIR="$2"; shift 2;;
        -o | --audio-only) A_ONLY="true"; shift ;;
        --) shift;
            until [[ -z "$1" ]]; do
                LINKS="${LINKS}${1}$IFS" ; shift
            done ; break ;;
        * ) shift ;;
    esac
done

TMP="/tmp"
FIFO="content-type"

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
    echo -e "   Specify your account password. If you upload as logged user, file"
    echo -e "   uploads will count towards your file stats on Volafile."
    echo -e "   See https://volafile.org/user/<your_username>\n"
    echo -e "-a, --upload-as <renamed_file>"
    echo -e "   Upload file with custom name.\n"
    echo -e "-d, --dir <destination_directory>"
    echo -e "   If you will specify this option, you will be prompted for each file you downloaded"
    echo -e "   to store it in given directory. Otherwise all your downloaded files will be"
    echo -e "   discarded after uploading them to Volafile.\n"
    echo -e "-o, --audio-only"
    echo -e "   If file you want forward to Volafile is a video, this option will strip video"
    echo -e "   stream from it and upload only audio stream.\n"
    exit 0
}

if [[ -z "$(which curlbar)" ]]; then
    cURL="curl"
else
    cURL="curlbar"
fi

ask_keep() {
    echo -e "Do you want to keep \033[1m$(basename "$1")\033[22m?"
    echo -e "File will be moved to \033[1m$VID_DIR\033[22m\n"
    while true; do
        printf "\033[32m[Y]es\033[0m/\033[31m[N]o\033[0m) " ; read -r yn
        case "$yn" in
            [Yy]*  ) mv "$1" "$VID_DIR" ; break;;
            [Nn]*  ) break ;;
            * )  continue ;;
        esac
    done
}

cleanup() {
    cd "$TMP" || exit
    for d in $DIR_LIST ; do
        rm -rf "$d"
    done
    trap - SIGHUP SIGTERM EXIT
    true # return prompt to default state if we interrupt our script
    exit
}

getContentType(){
    rm -f "$FIFO"
    mkfifo "$FIFO"
    local filetype
    local curl_pid
    ( set +e
    curl -sLI "$1" >> "$FIFO"
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
    trap cleanup ERR
    lastredirect=1
    while IFS=' ' read -r -a line; do
        if [[ "${line[1]}" == "200" ]]; then
            lastredirect=0
        fi
        if [[ $lastredirect -eq 0 ]] && [[ "${line[0]}" == "content-type:" ]]; then
            filetype=$(echo "${line[1]}" | tr -d ';')
        fi
    done
    sync
    rm -f "$FIFO"
    kill -9 "$curl_pid" 2>/dev/null || true
    echo "$filetype"
    }
}

youtube-dlBar() {
youtube-dl --newline -o "%(title)s.%(ext)s" -f "$1" "$2" 2>&1 | \
    sed -nu \
    -e '/^\[download\]/p' \
    -e '/^WARNING:/p' \
    -e '/^ERROR:/p' \
    -e '/^\[ffmpeg\]/p'| \
{
re='[0-9\.%~]{1,4}'
while IFS=' ' read -r -a line; do
    if [[ "${line[1]}" == "100%" ]]; then
        printf "\x1B[0G %-5s\x1B[7m%*s\x1B[27m%*s of %9s at %9s %8s ETA\x1B[0K\x1B[${curpos}G\n\n" \
        "${percent%%.*}%" "$on" "" "$off" "" "${line[3]//[~]}" "${line[5]}" "${line[7]}"
    elif [[ "${line[1]}" =~ $re ]]; then
        local percent="${line[1]//%}"
        local width=$(( $(tput cols) - 50 ))
        local curpos=$((width + 6))
        local filesize="${line[3]//[a-zA-Z~]}"
        local bytes=$( bc <<< "scale=2; ${line[1]%*%} * $filesize / 100" )
        local on=$( bc <<< "$bytes * $width / $filesize" )
        local off=$( bc <<< "$width - $on" )
        printf "\x1B[0G %-5s\x1B[7m%*s\x1B[27m%*s of %9s at %9s %8s ETA\x1B[0K\x1B[${curpos}G" \
        "${percent%%.*}%" "$on" "" "$off" "" "${line[3]//[~]}" "${line[5]}" "${line[7]}"
    elif [[ ${line[1]} == "Requested" ]]; then
        echo -e "Video and audio streams will be downloaded separately and merged together."
    elif [[ ${line[0]} == "ERROR:" ]]; then
        echo -e "\n\033[31m${line[@]:1}. Closing script.\033[0m\n"; return 1
    else
        echo -e "${line[@]:1}"
    fi
    ((++i))
done
IFS="$(printf '\r')"
return 0
}
}

postStuff() {
    if [[ $A_ONLY == "true" ]]; then
        local arg="bestaudio/wav/mp4/ogg/m4a/webm"
    else
        local arg="bestvideo[ext=mp4]+bestaudio[ext=m4a]/mp4/webm"
    fi
    cd "$TMP" || cleanup
    for l in $LINKS ; do
        local dir="tmp_${RANDOM}${RANDOM}"
        DIR_LIST="${DIR_LIST}${dir}$IFS"
        mkdir -p "$dir"
        cd "$dir" || cleanup
        echo -e "\n\033[32m<v> Downloading to \033[1m$TMP/$dir\033[22m\n"
        printf "\033[33m"
        ftype="$(getContentType "$l")"
        if [[ "$ftype" == "text/html" ]]; then
            youtube-dlBar "$arg" "$l"
        else
            $cURL -L "$l" > "$(basename "$l")"
        fi
        if [[ "$?" -ne 0 ]]; then
            cleanup
        fi
        printf "\033[0"
        #shellcheck disable=SC2012
        file="$(ls -t | head -qn 1)"
        FILE_LIST="${FILE_LIST}${dir}/${file}$IFS"
        cd ..
    done
    #shellcheck disable=SC2086
    set -- $ASS
    for f in $FILE_LIST ; do
        if [[ -n "$1" ]]; then
            ARG_PREP="${ARG_PREP}-a$IFS${1}$IFS${f}$IFS" ; shift
        else
            ARG_PREP="${ARG_PREP}${f}$IFS"
        fi

    done
    printf "\n"
    printf "%s" "$ARG_PREP" | xargs -d "$IFS" volaupload.sh \
        -r "$ROOM" -n "$NICK" -p "$PASSWORD"  || cleanup
    if [[ ! -d "$VID_DIR" ]] ; then
        for f in $FILE_LIST ; do
            ask_keep "$f"
        done
    fi
}

trap cleanup SIGHUP SIGTERM SIGINT EXIT

if [[ -n $HELP ]]; then
    print_help
elif [[ -z "$LINKS" ]]; then
    echo -e "\nMy dude, comon. You tried to download nothing.\n" ; exit 1
else
    postStuff
fi
