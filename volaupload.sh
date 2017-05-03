#!/usr/bin/env bash
#shellcheck disable=SC2086

if ! OPTS=$(getopt --options hu:r:cn:p:a:t:wm \
    --longoptions help,upload:,room:,call,nick:,password:,upload-as:,retries:,watch,most-new \
    -n 'volaupload.sh' -- "$@") ; then
    echo -e "\nFiled parsing options.\n" ; exit 1
fi

######################################################################################
# You can add ROOM, NICK and/or PASSWORD variable to your shell config as such:      #
# export ROOM="BEEPi" ; export NICK="dude" ; export PASSWORD="cuck" so you wouldn't  #
# have to pass them every time you want to upload something. Using parameters will   #
# override variables from the shell config. This inherently applies to stuff2vola.sh #
######################################################################################

#Remove space from IFS so we can upload files that contain spaces.
#I use little hack here, I replaced default separator from space to
#carrige return so we can iterate over the TARGETS variable without
#a fear of splitting filenames.

IFS="$(printf '\r')"
eval set -- "$OPTS"

SERVER="https://volafile.org"
COOKIE="/tmp/cuckie"
RETRIES="3"

while true; do
    case "$1" in
        -h | --help) HELP="true" ; shift ;;
        -u | --upload) TARGETS="${TARGETS}${2}$IFS" ; shift 2 ;;
        -r | --room)
            p="https?://volafile.org/r/([a-zA-Z0-9_-]{3,20}$)"
            if [[ "$2" =~ $p ]]; then
                ROOM="${BASH_REMATCH[1]}"
            else
                pe="^[a-zA-Z0-9_-]{3,20}$"
                if [[ "$2" =~ $pe ]]; then
                    ROOM="${BASH_REMATCH[0]}"
                else
                    echo -e "\n\033[31mSorry my dude, but your room ID doesn't match Volafile's format!\033[31m\n" >&2
                    exit 2
                fi
            fi ; shift 2 ;;
        -c | --call) CALL="true"; shift ;;
        -n | --nick) NICK="$2" ; shift 2 ;;
        -p | --password) PASSWORD="$2" ; shift 2 ;;
        -a | --upload-as) RENAMES="${RENAMES}${2}$IFS" ; shift 2 ;;
        -t | --retries) RETRIES="$2"
            re="^[0-9]$"
            if ! [[ "$RETRIES" =~ $re ]] || [[ "$RETRIES" -lt 0 ]]; then
                echo -e "\n\033[31mYou wanted to set negative number of retries or ..." >&2
                echo -e "... exceeded maximum retry count.\033[0m\n" >&2
                exit 3
            fi ; shift 2 ;;
        -w | --watch) WATCHING="true" ; shift ;;
        -m | --most-new) NEWEST="true" ; shift ;;
        --) shift;
            until [[ -z "$1" ]]; do
                TARGETS="${TARGETS}${1}$IFS" ; shift
            done ; break ;;
        * ) shift ;;
    esac
done

proper_exit() { rm -f "$COOKIE"; exit 0; }

failure_exit() {
    local failure
    for failure in "$@"; do
        echo -e "\033[31m$failure\033[0m" >&2
    done; rm -f "$COOKIE"; exit 4;
}

#Return non zero value when script gets interrupted with Ctrl+C or some error occurs
# and remove the cookie
trap failure_exit SIGHUP SIGINT SIGTERM

#remove cookie on server error to get fresh session for next upload
skip() {
    local omit
    for omit in "$@"; do
        echo -e "\033[31m$omit\033[0m" >&2
    done; rm -f "$COOKIE"
}

handleErrors() {
    case $1 in
        0  ) ;;
        6  ) failure_exit "\nCheck your interwebz connection, my friendo!" \
                "Either that, or volafile is dead.\n" ;;
        22 ) failure_exit "\nRoom with ID you specified doesn't exist.\n" ;;
        101) failure_exit "\nLogin Error: You used wrong login and/or password my dude." \
                "You wanna login properly, so those sweet volastats can stack up!\n" ;;
        *  ) failure_exit "\ncURL error of code $1 happend.\n" ;;
    esac
}

if [[ -z "$(which curlbar)" ]]; then
    cURL="curl"
else
    cURL="curlbar"
fi

if [[ -n "$ROOM" ]]; then
    roomHTML=$(curl -fsLH "Referer: https://volafile.org" -H "Accept: text/values" \
        "https://volafile.org/r/$ROOM")
    handleErrors "$?"
    ROOM=$(echo "$roomHTML" | grep -oP '\"room_id\":\"[a-zA-Z0-9-_]+\"' | \
        sed 's/\(\"room_id\"\:\|\"\)//g')
fi

print_help() {
    echo -e "\nvolaupload.sh help page\n"
    echo -e "-h, --help"
    echo -e "   Show this help message.\n"
    echo -e "-u, --upload <upload_target>"
    echo -e "   Upload a file or whole directory. Every argument that is not prepended"
    echo -e "   with suitable option will be treated as upload target.\n"
    echo -e "-r, --room <room_name>"
    echo -e "   Specifiy upload room. (This plus at least one upload target is the only"
    echo -e "   required option to upload something).\n"
    echo -e "-c, --call <method> <query>"
    echo -e "   Make Rest API call.\n"
    echo -e "-n, --nick <name>"
    echo -e "   Specify name, under which your file(s) will be uploaded.\n"
    echo -e "-p, -pass <password>"
    echo -e "   Specify your account password. If you upload as logged user, file"
    echo -e "   uploads will count towards your file stats on Volafile."
    echo -e "   See https://volafile.org/user/<your_username>\n"
    echo -e "-a, --upload-as <renamed_file>"
    echo -e "   Upload file with custom name. (It won't overwrite the filename in your"
    echo -e "   fielsystem). You can upload multiple renamed files.\n"
    echo -e "   Example:"
    echo -e "       volaupload.sh -r BEPPi file1.jpg file2.png -a funny.jpg -a nasty.png"
    echo -e "   First occurence of -a parameter always renames first given file and so on.\n"
    echo -e "-t, --retries <number>"
    echo -e "   Specify number of retries when upload fails. Defaults to 3."
    echo -e "   You can't retry more than 9 times.\n"
    echo -e "-w, --watch <directory>"
    echo -e "   Makes your script to watch over specific directory. Every file added"
    echo -e "   to that directory will be uploaded to Volafile. (To exit press Ctrl+C)\n"
    echo -e "-m, --most-new <directory>"
    echo -e "   Uploads only the first file that was recently modified in specified directory\n"
    exit 0
}

bad_arg() {
    echo -e "\n\033[33;1m${1}\033[22m: This argument isn't a file or a directory. Skipping ...\033[0m\n"
    echo -e "Use -h or --help to check program usage.\n"
}

extract() {
    _key=$2
    echo "$1" | (while read -r line; do
        b="$(echo "$line" | cut -d'=' -f1)"
        if [[ "$b" == "$_key" ]]; then
            printf "%s" "$line" | cut -d'=' -f2
            return;
        fi
        done)
}

makeApiCall() {
    local method="$1"
    local query="$2"
    local name="$3"
    local password="$4"
    if [[ -n "$name" ]] && [[ -n "$password" ]]; then
        #session "memoization"
        if [[ ! -f "$COOKIE" ]]; then
            curl -1L -H "Origin: ${SERVER}" \
            -H "Referer: ${SERVER}" -H "Accept: text/values" \
            "${SERVER}/rest/login?name=${name}&password=${password}" 2>/dev/null | \
            cut -d$'\n' -f1 > "$COOKIE"
        fi
        cookie="$(head -qn 1 "$COOKIE")"
        if [[ "$cookie" == "error.code=403" ]]; then
            return 101
        fi
        curl -1L -b "$cookie" -H "Origin: ${SERVER}" -H "Referer: ${SERVER}" \
            -H "Accept: text/values" "${SERVER}/rest/${method}?${query}" 2>/dev/null
    else
        curl -1L -H "Origin: ${SERVER}" -H "Referer: ${SERVER}" -H "Accept: text/values" \
            "${SERVER}/rest/${method}?${query}" 2>/dev/null
    fi
}

doUpload() {
    local file="$1"
    local room="$2"
    local name="$3"
    local pass="$4"
    local renamed="$5"

    if [[ -n "$name" ]] && [[ -n "$pass" ]]; then
        local response; response=$(makeApiCall getUploadKey "name=$name&room=$room" "$name" "$pass")
    elif [[ -n "$name" ]]; then
        local response; response=$(makeApiCall getUploadKey "name=$name&room=$room")
    else
        #If user didn't specify name, default it to Volaphile.
        name="Volaphile"
        local response; response=$(makeApiCall getUploadKey "name=$name&room=$room")
    fi
    handleErrors "$?"

    local error; error=$(extract "$response" "error.code")

    if [[ -n "$error" ]]; then
        local errmsg; errmsg=$(extract "$response" "error.message")
        failure_exit "\n$error Server Error" "$errmsg\n"
    fi

    local server; server="https://$(extract "$response" server)"
    local key; key=$(extract "$response" key)
    local file_id; file_id=$(extract "$response" file_id)

    # -f option makes curl return error 22 on server responses with code 400 and higher
    if [[ -z "$renamed" ]]; then
        echo -e "\033[32m<^> Uploading \033[1m$(basename "$file")\033[22m to \033[1m$ROOM\033[22m as \033[1m$name\033[22m\n"
        printf "\033[33m" 2>&1 #curlbar prints stuff to stderr so we change color for stdout and stderr
        $cURL -1fL -H "Origin: ${SERVER}" -F "file=@\"${file}\"" \
            "${server}/upload?room=${room}&key=${key}" 1>/dev/null
        error="$?"
    else
        echo -e "\033[32m<^> Uploading \033[1m$(basename "$file")\033[22m to \033[1m$ROOM\033[22m as \033[1m$name\033[22m\n"
        echo -e "-> File renamed to: \033[1m${renamed}\033[22m\n"
        printf "\033[33m" 2>&1
        $cURL -1fL -H "Origin: ${SERVER}" -F "file=@\"${file}\";filename=\"${renamed}\"" \
            "${server}/upload?room=${room}&key=${key}" 1>/dev/null
        error="$?"
        file="$renamed"
    fi
    printf "\033[0m"
    case $error in
        0 ) #Replace spaces with %20 so my terminal url finder can see links properly.
              file=$(basename "$file" | sed -r "s/ /%20/g" )
              printf "\n\033[35mVola direct link:\033[0m\n"
              printf "\033[1m%s/get/%s/%s\033[0m\n\n" "$SERVER" "$file_id" "$file" ;;
        1 ) skip "Some strange TLS error, continuing." ;;
        6 ) failure_exit "\nRoom with ID of \033[1m$ROOM\033[22m doesn't exist! Closing script.\n" ;;
        22) skip "\nServer error. Usually caused by gateway timeout.\n" ;;
        * ) skip "\nError nr \033[1m${error}\033[22m: Upload failed!\n" ;;
    esac
    return $error
}

tryUpload() {
    local i=0
    while ((i<RETRIES)); do
        if doUpload "$1" "$2" "$3" "$4" "$5" ; then
            return
        fi
        ((++i))
        echo "Retrying upload after 5 seconds..."
        sleep 5
        wait
    done
    failure_exit "\nExceeded number of retries... Closing script."
}

getExtension() {
    if [[ "${2##*.}" == "$2" ]]; then
        printf "%s" "$1"
    else
        printf "%s" "${1%%.*}.${2##*.}"
    fi
}

howmany() ( set -f; set -- $1; echo $# )
declare -i argc
argc=$(howmany "$TARGETS")

if [[ $argc == 0 ]] || [[ -n $HELP ]]; then
    print_help
elif [[ -z "$NICK" ]] && [[ -n "$PASSWORD" ]]; then
    failure_exit "\nSpecifying password, but not a username? What are you? A silly-willy?\n"
elif [[ -n "$WATCHING" ]] && [[ -n "$ROOM" ]] && [[ $argc == 1 ]]; then
    if [[ -z "$(which inotifywait)" ]]; then
        failure_exit "\nPlease install inotify-tools package in order to use this feature.\n"
    fi
    TARGET=$(echo "$TARGETS" | tr -d "\r")
    if [[ -d "$TARGET" ]]; then
        inotifywait -m -e close_write -e moved_to --format '%w%f' "$TARGET" | \
            while read -r dir file; do
                tryUpload "${dir}${file}" "$ROOM" "$NICK" "$PASSWORD"
            done
        else
        failure_exit "\nYou have to specify the directory that can be watched.\n"
    fi
elif [[ $argc == 2 ]] && [[ -n "$CALL" ]]; then
    set -f ; set -- $TARGETS
    makeApiCall "$1" "$2"
    handleErrors "$?"
    proper_exit
elif [[ $argc -gt 0 ]] && [[ -z "$WATCHING" ]] && [[ -z "$CALL" ]]; then
    set -- $RENAMES
    for t in $TARGETS ; do
        if [[ -d "$t" ]] && [[ -n "$NEWEST" ]]; then
            file=$(find "$t" -maxdepth 1 -type f -printf '%T@ %p\n' \
                | sort -n | tail -n1 | cut -d' ' -f2-)
            tryUpload "$file" "$ROOM" "$NICK" "$PASSWORD"
        elif [[ -d "$t" ]]; then
            shopt -s globstar
            GLOBIGNORE=".:.."
            for f in "${t}"/** ; do
                if [[ -f "$f" ]] && [[ -n "$1" ]]; then
                    tryUpload "${f}" "$ROOM" "$NICK" "$PASSWORD" "$(getExtension "$1" "$f")" ; shift
                elif [[ -f "$f" ]]; then
                    tryUpload "${f}" "$ROOM" "$NICK" "$PASSWORD"
                fi
            done
        elif [[ -f "$t" ]] && [[ -n "$1" ]]; then
            tryUpload "$t" "$ROOM" "$NICK" "$PASSWORD" "$(getExtension "$1" "$t")" ; shift
        elif [[ -f "$t" ]]; then
            tryUpload "$t" "$ROOM" "$NICK" "$PASSWORD"
        else
            bad_arg "$t" ; shift
        fi
    done
    proper_exit
else
    print_help
fi
