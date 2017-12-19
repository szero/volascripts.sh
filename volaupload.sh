#!/usr/bin/env bash

# shellcheck disable=SC2034
__VOLAUPLOADSH_VERSION__=1.7

if ! OPTS=$(getopt --options hr:cn:p:u:a:t:wm \
    --longoptions help,room:,call,nick:,pass:,room-pass:,upload-as:,retries:,watch,most-new \
    -n 'volaupload.sh' -- "$@") ; then
    echo -e "\nFiled parsing options.\n" ; exit 1
fi

if [[ -f "$HOME/.volascriptsrc" ]]; then
    #shellcheck disable=SC1090
    source "$HOME/.volascriptsrc"
fi

#Remove space from IFS so we can upload files that contain spaces.
#I use little hack here, I replaced default separator from space to
#carrige return so we can iterate over the TARGETS variable without
#a fear of splitting filenames.
IFS=$'\r'

if [ -z "$TMPDIR" ]; then
    TMP="/tmp"
else
    TMP="${TMPDIR%/}"
fi

SERVER="https://volafile.org"
COOKIE="$TMP/cuckie_$(head -c4 <(tr -dc '[:alnum:]' < /dev/urandom))"
RETRIES="3"

#Return non zero value when script gets interrupted with Ctrl+C or some error occurs
# and remove the cookie
handle_exit() {
    trap - SIGHUP SIGINT SIGTERM
    local failure
    local exit_code="$1"
    if [[ "$exit_code" == "" ]]; then
        echo -e "\n\033[0mProgram interrupted by user."
        exit_code=10
    fi
    for failure in "${@:2}"; do
        echo -e "\033[31m$failure\033[0m" >&2
    done; rm -f "$COOKIE" "$stuff" ;  exit "$exit_code"
}

eval set -- "$OPTS"

while true; do
    case "$1" in
        -h | --help) HELP="true" ; shift ;;
        -r | --room)
            if [[ "$2" =~ [a-zA-Z0-9_-]{1,20}$ ]]; then
                ROOM="${BASH_REMATCH[0]}"
            else
                handle_exit "2" "Sorry my dude, but your room ID doesn't match Volafile's format!\n"
            fi ; shift 2 ;;
        -c | --call) CALL="true"; shift ;;
        -n | --nick) NICK="$2"; shift 2 ;;
        -p | --pass) PASSWORD="$2"; shift 2 ;;
        -u | --room-pass) ROOMPASS="$2"; shift 2 ;;
        -a | --upload-as) RENAMES+=("$2"); shift 2 ;;
        -t | --retries) RETRIES="$2"
            re="^[0-9]$"
            if ! [[ "$RETRIES" =~ $re ]] || [[ "$RETRIES" -lt 0 ]]; then
                handle_exit "3" "You wanted to set negative number of retries or ..." \
                "... exceeded maximum retry count.\n"
            fi ; shift 2 ;;
        -w | --watch) WATCHING="true" ; shift ;;
        -m | --most-new) NEWEST="true" ; shift ;;
        --) shift;
            until [[ -z "$1" ]]; do
                TARGETS+=("$1") ; shift
            done ; break ;;
        * ) shift ;;
    esac
done

trap handle_exit SIGHUP SIGINT SIGTERM

#remove cookie on server error to get fresh session for next upload
skip() {
    local omit
    for omit in "$@"; do
        echo -e "\033[31m$omit\033[0m" >&2
    done; rm -f "$COOKIE"
}

if [[ $(type curlbar 2>/dev/null) ]]; then
    cURL="curlbar"
else
    cURL="curl"
fi

print_help() {
cat >&2 << EOF

volaupload.sh help page

   Upload files or whole directories to volafile. Every argument that is
   not prepended with any option will be treated as upload target.

-h, --help
   Show this help message.

-r, --room <room_name>
   Specifiy upload room. (This plus at least one upload target is the only
   required option to upload something).

-c, --call <method> <query>
   Make Rest API call.

-n, --nick <name>
   Specify name, under which your file(s) will be uploaded.

-p, --pass <password>
   Set your account password. If you upload as logged user, file
   uploads will count towards your file statistics on Volafile.
   See https://volafile.org/user/<your_username>

-u, --room-pass <password>
    You need to specify this only for password protected rooms.

-a, --upload-as <renamed_file>
   Upload file with custom name. (It won't overwrite the filename in your
   fielsystem). You can upload multiple renamed files.
   Example:
       volaupload.sh -r BEEPi file1.jpg file2.png -a funny.jpg -a nasty.png
   First occurence of -a parameter always renames first given file and so on.

-t, --retries <number>
   Specify number of retries when upload fails. Defaults to 3.
   You can't retry more than 9 times.

-w, --watch <directory>
   Makes your script to watch over specific directory. Every file added
   to that directory will be uploaded to Volafile. (To exit press Ctrl+C)

-m, --most-new <directory>
   Uploads only the first file that was recently modified in specified directory

EOF
exit 0
}

extract() {
    _key=$2
    echo "$1" | (while read -r line; do
        b="$(echo "$line" | cut -d'=' -f1)"
        if [[ "$b" == "$_key" ]]; then
            printf "%s" "$line" | cut -d'=' -f2
            return
        fi
        done)
}

makeApiCall() {
    local method="$1"
    local query="$2"
    local room="$3"
    local name="$4"
    local password="$5"
    if [[ -n "$room" ]]; then
        local ref="Referer: ${SERVER}/r/${room}"
    else
        local ref="Referer: ${SERVER}"
    fi

    if [[ -n "$name" ]] && [[ -n "$password" ]]; then
        #session "memoization"
        if [[ ! -f "$COOKIE" ]]; then
            curl -1L -H "Origin: ${SERVER}" -H "$ref" -H "Accept: text/values" \
            "${SERVER}/rest/login?name=${name}&password=${password}" 2>/dev/null | \
            cut -d$'\n' -f1 > "$COOKIE"
        fi
        cookie="$(head -qn 1 "$COOKIE")"
        if [[ "$cookie" == "error.code=403" ]]; then
            return 101
        fi
        curl -1L -b "$cookie" -H "Origin: ${SERVER}" -H "$ref" \
            -H "Accept: text/values" "${SERVER}/rest/${method}?${query}" 2>/dev/null
    else
        curl -1L -H "Origin: ${SERVER}" -H "$ref" \
            -H "Accept: text/values" "${SERVER}/rest/${method}?${query}" 2>/dev/null
    fi
}

doUpload() {

    trap handle_exit SIGINT

    local file="$1"
    local room="$2"
    local name="$3"
    local pass="$4"
    local roompass="$5"
    local renamed="$6"
    local response
    local error
    if [[ -n "$roompass" ]]; then
        roompass="&password=$roompass"
    fi
    if [[ -n "$name" ]] && [[ -n "$pass" ]]; then
        response=$(makeApiCall getUploadKey "name=$name&room=$room$roompass" "$room" "$name" "$pass")
    elif [[ -n "$name" ]]; then
        response=$(makeApiCall getUploadKey "name=$name&room=$room$roompass" "$room")
    else
        #If user didn't specify name, default it to Volaphile.
        name="Volaphile"
        response=$(makeApiCall getUploadKey "name=$name&room=$room$roompass" "$room")
    fi
    error="$?"
    case "$error" in
        0  ) ;;
        6  ) echo "106"; echo "Check your interwebz connection, my friendo!"
             echo "Either that, or volafile is dead.#"; return ;;
        101) echo "101"; echo "Login Error: You used wrong login and/or password my dude."
             echo "You wanna login properly, so those sweet volastats can stack up!#";  return;;
        *  ) echo "105"; echo "cURL error of code $error happend.#"; return ;;
    esac
    error=$(extract "$response" "error.code")
    if [[ "$error" == "429" ]]; then
        echo "103"; echo "$(extract "$response" "error.info.timeout")#"
        return
    elif [[ -n "$error" ]]; then
        echo "104"; echo -e "Error number $error. $(extract "$response" "error.message")#"
        return
    fi

    local server; server="https://$(extract "$response" server)"
    local key; key=$(extract "$response" key)
    local file_id; file_id=$(extract "$response" file_id)

    # -f option makes curl return error 22 on server responses with code 400 and higher
    if [[ -z "$renamed" ]]; then
        echo -e "\033[32m</\\> Uploading \033[1m$(basename "$file")\033[22m to \033[1m$ROOM\033[22m as \033[1m$name\033[22m" >&2
        printf "\033[33m" >&2 #curlbar prints stuff to stderr so we change color in that descriptor
        $cURL -1fL -H "Origin: ${SERVER}" -F "file=@\"${file}\"" \
            "${server}/upload?room=${room}&key=${key}" 1>/dev/null
        error="$?"
    else
        echo -e "\033[32m</\\> Uploading \033[1m$(basename "$file")\033[22m to \033[1m$ROOM\033[22m as \033[1m$name\033[22m" >&2
        echo -e "-> File renamed to: \033[1m${renamed}\033[22m" >&2
        printf "\033[33m" >&2
        $cURL -1fL -H "Origin: ${SERVER}" -F "file=@\"${file}\";filename=\"${renamed}\"" \
            "${server}/upload?room=${room}&key=${key}" 1>/dev/null
        error="$?"
        file="$renamed"
    fi
    printf "\033[0m" >&2
    case $error in
        0 | 102) #Replace spaces with %20 so my terminal url finder can see links properly.
            if [[ $error -eq 102 ]]; then
                printf "\033[33mFile was too small to make me bothered with printing the progress bar.\033[0m\n" >&2
            fi
            file=$(basename "$file" | sed -r "s/ /%20/g" )
            printf "\n\033[35mVola direct link:\033[0m\n" >&2
            printf "\033[1m%s/get/%s/%s\033[0m\n\n" "$SERVER" "$file_id" "$file" >&2 ;;
        22) skip "\nServer error. Usually caused by gateway timeout.\n" ;;
        * ) skip "\nError nr \033[1m${error}\033[22m: Upload failed!\n" ;;
    esac
    echo "${error}#"
}

tryUpload() {
    local -i i=0
    while ((i<RETRIES)); do
        # first argument of 'handle' is error code
        # second and later arguments are whatever
        { local IFS=$'\n'; read -r -d'#' -a handle
        if [[ ${handle[0]} == "0" ]] || [[ ${handle[0]} == "102" ]] ; then
            return
        elif [[ ${handle[0]} == "101" ]] || [[ ${handle[0]} == "104" ]] \
            || [[ ${handle[0]} == "105" ]] || [[ ${handle[0]} == "106" ]]; then
            handle_exit "${handle[@]}"
        elif [[ ${handle[0]} == "103" ]]; then
            local penalty
            penalty="$(bc <<< "(${handle[1]}/1000)+1")"
            printf "\033[33m"
            while [[ $penalty -gt 0 ]]; do
                printf "\033[0GToo many key requests, hotshot. Gotta wait %s seconds now...\033[0K" \
                    "$((--penalty))" >&2
                sleep 1
            done
            printf "\033[0G\033[2K\033[0m"
        else
            echo -e "\033[33mcURL error nr ${handle[0]} happend.\033[0m\n" >&2
            echo -e "\033[33mRetrying upload after 5 seconds ...\033[0m\n" >&2
            sleep 5
        fi
        } < <(doUpload "$1" "$2" "$3" "$4" "$5" "$6")
        ((++i))
    done
    handle_exit "8" "Exceeded maximum number of retries... Closing script."
}

getExtension() {
    if [[ "${2##*.}" == "$2" ]]; then
        printf "%s" "$1"
    else
        printf "%s" "${1%%.*}.${2##*.}"
    fi
}

declare -i argc
argc=${#TARGETS[@]}

if [[ -n "$HELP" ]]; then
    print_help
elif [[ $argc -eq 0 ]]; then
    handle_exit "4" "You didn't specify any files that can be uploaded!\n"
elif [[ $argc == 2 ]] && [[ -n "$CALL" ]]; then
    set -f ; set -- "${TARGETS[@]}"
    declare -i error
    makeApiCall "$1" "$2"; error="$?"
    if [[ "$error" -ne 0 ]]; then
        handle_exit "$?" "cURL error of code $error happend."
    fi
    handle_exit "0"
fi
if [[ ${#ROOM_ALIASES[@]} -gt 0 ]]; then
    for a in "${ROOM_ALIASES[@]}"; do
        if [[ "$ROOM" == "$(echo "$a" | cut -d'=' -f1)" ]]; then
            ROOM="$(echo "$a" | cut -d'=' -f2)"
            break
        fi
    done
fi
if [[ -n "$ROOM" ]] ; then
    if ! ROOM=$(curl -fsLH "Referer: $SERVER" -H "Accept: text/values" \
        "$SERVER/r/$ROOM" | grep -oP "\"room_id\s*\"\s*:\s*\"\K[a-zA-Z0-9-_]+(?=\",)"); then
        handle_exit "5" "Room you specified doesn't exist, or Vola is busted for good this time!\n"
    fi
fi
if [[ -z "$NICK" ]] && [[ -n "$PASSWORD" ]]; then
    handle_exit "4" "Specifying password, but not a username? What are you? A silly-willy?\n"
elif [[ -n "$WATCHING" ]] && [[ -n "$ROOM" ]] && [[ $argc == 1 ]]; then
    if [[ -z "$(which inotifywait)" ]]; then
        handle_exit "6" "Please install inotify-tools package in order to use this feature.\n"
    fi
    TARGET=$(echo "${TARGETS[0]}" | tr -d "\r")
    if [[ -d "$TARGET" ]]; then
        declare stop_double_upload=""
        inotifywait -m -e moved_to -e create --format '%w%f' "$TARGET" | \
            while read -r dir file; do
                if [[ $stop_double_upload != "${dir}${file}" ]]; then
                    tryUpload "${dir}${file}" "$ROOM" "$NICK" "$PASSWORD" "$ROOMPASS"
                fi
                stop_double_upload="${dir}${file}"
            done
    else
        handle_exit "7" "You have to specify the directory that can be watched.\n"
    fi
elif [[ $argc -gt 0 ]] && [[ -z "$WATCHING" ]] && [[ -z "$CALL" ]]; then
    set -- "${RENAMES[@]}"
    for t in "${TARGETS[@]}" ; do
        if [[ -d "$t" ]] && [[ -n "$NEWEST" ]]; then
            file=$(find "$t" -maxdepth 1 -type f -printf '%T@ %p\n' \
                | sort -n | tail -n1 | cut -d' ' -f2-)
            if [[ -n "$1" ]]; then
                tryUpload "$file" "$ROOM" "$NICK" "$PASSWORD" "$ROOMPASS" "$(getExtension "$1" "$file")"
            else
                tryUpload "$file" "$ROOM" "$NICK" "$PASSWORD" "$ROOMPASS"
            fi
        elif [[ -d "$t" ]]; then
            shopt -s globstar
            GLOBIGNORE=".:.."
            for f in "${t}"/** ; do
                if [[ -f "$f" ]] && [[ -n "$1" ]]; then
                    tryUpload "${f}" "$ROOM" "$NICK" "$PASSWORD" "$ROOMPASS" "$(getExtension "$1" "$f")" ; shift
                elif [[ -f "$f" ]]; then
                    tryUpload "${f}" "$ROOM" "$NICK" "$PASSWORD" "$ROOMPASS"
                fi
            done
        elif [[ -f "$t" ]] && [[ -n "$1" ]]; then
            tryUpload "$t" "$ROOM" "$NICK" "$PASSWORD" "$ROOMPASS" "$(getExtension "$1" "$t")" ; shift
        elif [[ -f "$t" ]] ; then
            tryUpload "$t" "$ROOM" "$NICK" "$PASSWORD" "$ROOMPASS"
        elif [[ "$(readlink "$t")" == "pipe:"* ]]; then
            stuff="$(mktemp)"
            cat "$t" > "$stuff"
            while read -r line; do
                rename=$(echo "$line" | tr -s " ")
                if [[ -n "$rename" ]]; then
                    break
                fi
            done < "$stuff"
            tryUpload "$stuff" "$ROOM" "$NICK" "$PASSWORD" "$ROOMPASS" "$rename"
        else
            echo -e "\n\033[33;1m${t}\033[22m: This argument isn't a file or a directory. Skipping ...\033[0m\n" >&2
            echo -e "Use -h or --help to check program usage.\n" >&2
            shift
        fi
    done
    handle_exit "0"
else
    print_help
fi
