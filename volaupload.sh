#!/usr/bin/env bash
#shellcheck disable=SC2086

if ! OPTS=$(getopt --options hu:r:cn:p:a:w \
--longoptions help,upload:,room:,call,nick:,password:,upload-as:,watch \
-n 'volaupload.sh' -- "$@") ; then
    echo -e "\nFiled parsing options.\n" ; exit 1
fi

#####################################################################################
# You can add ROOM, NICK and/or PASSWORD variable to your shell config as such:     #
# export ROOM="BEEPi" ; export NICK="dude" ; export PASSWORD="cuck" so you wouldn't #
# have to pass them every time you want to upload something. Using parameters will  #
# override variables in your shell config.                                          #
#####################################################################################

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
    echo -e "   See https://volafile.io/user/<your_username>\n"
    echo -e "-a, --upload-as <renamed_file>"
    echo -e "   Upload file with custom name. (It won't overwrite the file in your"
    echo -e "   fielsystem). You can upload only one file if this option is set.\n"
    echo -e "-w, --watch <directory>"
    echo -e "   Makes your script to watch over specific directory. Every file added"
    echo -e "   to that directory will be uploaded to Volafile. (To exit press Ctrl+Z)\n"
    exit 0
}

upload_error() {
    echo -e "\n${1}: This argument isn't a file or a directory. Skipping ..."
    echo -e "Use -h or --help to check program usage.\n"
}

SERVER="https://volafile.io"
COOKIE="/tmp/cuckie"

proper_exit() { rm -f "$COOKIE"; exit 0; }
failure_exit() { rm -f "$COOKIE"; exit 1; }
#Return non zero value when script gets interrupted with Ctrl+C
trap failure_exit INT

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
    method=$1
    query=$2
    name=$3
    password=$4
    if [[ -n "$name" ]] && [[ -n "$password" ]]; then
        #session "memoization"
        if [[ ! -f "$COOKIE" ]]; then
            curl -1 -H "Origin: ${SERVER}" \
            -H "Referer: ${SERVER}" -H "Accept: text/values" \
            "${SERVER}/rest/login?name=${name}&password=${password}" 2>/dev/null |
            cut -d$'\n' -f1 > "$COOKIE"
        fi
        cookie="$(head -qn 1 "$COOKIE")"
        if [[ "$cookie" == "error.code=403" ]]; then
            return 1
        fi
        curl -1 -b "$cookie" -H "Origin: ${SERVER}" -H "Referer: ${SERVER}" \
            -H "Accept: text/values" "${SERVER}/rest/${method}?${query}" 2>/dev/null
    else
        curl -1 -H "Origin: ${SERVER}" -H "Referer: ${SERVER}" -H "Accept: text/values" \
            "${SERVER}/rest/${method}?${query}" 2>/dev/null
    fi
}

doUpload() {
    file="$1"
    room="$2"
    name="$3"
    pass="$4"
    renamed="$5"

    if [[ -n "$name" ]] && [[ -n "$pass" ]]; then
        response=$(makeApiCall getUploadKey "name=$name&room=$room" "$name" "$pass")
    elif [[ -n "$name" ]]; then
        response=$(makeApiCall getUploadKey "name=$name&room=$room")
    else
        #If user didn't specify name, default it to Volaphile.
        name="Volaphile"
        response=$(makeApiCall getUploadKey "name=$name&room=$room")
    fi

    #shellcheck disable=SC2181
    if [[ "$?" != "0" ]]; then
        echo -e "\nLogin Error: You used wrong login and/or password my dude."
        echo -e "You wanna login properly, so those sweet volastats can stack up!\n"
        failure_exit
    fi

    error=$(extract "$response" error)

    if [[ -n "$error" ]]; then
        echo "Error: $error"
        failure_exit
    fi

    server=$(extract "$response" server)
    server="https://${server}"
    key=$(extract "$response" key)
    file_id=$(extract "$response" file_id)

    # -f option makes curl return error 22 on server responses with code 400 and higher
    if [[ -n "$renamed" ]]; then
        echo -e "\n-- Uploading as $name: $file"
        echo -e "-- File renamed to: ${renamed}\n"
        curl --http2 -1 -f -H "Origin: ${SERVER}" -F "file=@\"${file}\";filename=\"${renamed}\"" \
            "${server}/upload?room=${room}&key=${key}" 1>/dev/null
        error="$?"
        file="$renamed"
    else
        echo -e "\n-- Uploading as $name: $file\n"
        curl --http2 -1 -f -H "Origin: ${SERVER}" -F "file=@\"${file}\"" \
            "${server}/upload?room=${room}&key=${key}" 1>/dev/null
        error="$?"
    fi
    case "$error" in #do something on error
        "0" ) #Replace spaces with %20 so my terminal url finder can see links properly.
              file=$(basename "$file" | sed -r "s/ /%20/g" )
              printf "\nVola direct link:\n"
              printf "%s/get/%s/%s\n\n" "$SERVER" "$file_id" "$file" ;;
        "6" ) printf "\nYou used wrong room ID! Closing script.\n\n" ; failure_exit ;;
        "22") printf "\nServer error. Usually caused by gateway timeout.\n\n" ; failure_exit ;;
        *   ) printf "\nError nr %s: Upload failed!\n\n" "$error" ; failure_exit ;;
    esac
}

#Remove space from IFS so we can upload files that contain spaces.
#I use little hack here, I replaced default separator from space to
#to carrige return so we can iterate over the TARGETS variable without
#a fear of splitting filenames.

IFS="$(printf '\r')"
eval set -- "$OPTS"

while true; do
  case "$1" in
    -h | --help) HELP="true" ; shift ;;
    -u | --upload) TARGETS="${TARGETS}${2}$(printf '\r')" ; shift 2 ;;
    -r | --room) ROOM="$2" ; shift 2 ;;
    -c | --call) CALL="true"; shift ;;
    -n | --nick) NICK="$2" ; shift 2 ;;
    -p | --password) PASSWORD="$2" ; shift 2 ;;
    -a | --upload-as) RENAMED_FILE="$2" ; shift 2 ;;
    -w | --watch) WATCHING="true" ; shift ;;
    -- ) shift;
        until [[ -z "$1" ]]; do
            TARGETS="${TARGETS}${1}$(printf '\r')" ; shift
        done ; break ;;
    * ) shift ;;
esac
done

howmany() ( set -f; set -- $1; echo $# )
declare -i argc
argc=$(howmany "$TARGETS")

if [[ $argc == 0 ]] || [[ -n $HELP ]]; then
    print_help
elif [[ -z "$ROOM" ]]; then
    echo -e "\nCan't upload stuff to nowhere my dude! Specify proper room ID, pretty please!\n"
    failure_exit
elif [[ -n "$WATCHING" ]] && [[ -n "$ROOM" ]] && [[ $argc == 1 ]]; then
    TARGET=$(echo "$TARGETS" | tr -d "\r")
    if [[ -d "$TARGET" ]]; then
        inotifywait -m "$TARGET" -e close_write -e moved_to |
            while read -r path _ file; do
                doUpload "${path}${file}" "$ROOM" "$NICK" "$PASSWORD"
            done
    fi
elif [[ -n $RENAMED_FILE ]] && [[ -n "$ROOM" ]] && [[ $argc == 1 ]]; then
    set -f ; set -- $TARGETS
    if [[ -f "$1" ]];  then
        doUpload "$1" "$ROOM" "$NICK" "$PASSWORD" "$RENAMED_FILE"
    else
        upload_error "$1"
    fi
    proper_exit
elif [[ $argc == 2 ]] && [[ -n $CALL ]]; then
    set -f ; set -- $TARGETS
    makeApiCall "$1" "$2"
    proper_exit
elif [[ $argc -gt 0 ]] && [[ -z "$WATCHING" ]] && \
     [[ -z "$RENAMED_FILE" ]] && [[ -z "$CALL" ]]; then
    for t in $TARGETS ; do
        if [[ -d "$t" ]]; then
            shopt -s globstar
            GLOBIGNORE=".:.."
            for f in "${t}"/**
            do
                if [[ -f "$f" ]]; then
                    doUpload "${f}" "$ROOM" "$NICK" "$PASSWORD"
                fi
            done
        elif [[ -f "$t" ]]; then
            doUpload "$t" "$ROOM" "$NICK" "$PASSWORD" "$RENAMED_FILE"
        else
            upload_error "$t"
        fi
    done
    proper_exit
else
    print_help
fi
