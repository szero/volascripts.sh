#!/usr/bin/env bash

if ! OPTS=$(getopt --options l:r:a:d:oy \
    --longoptions link:,room:,upload-as:,dir:,audio-only,yes -n 'vid2vola.sh' -- "$@"); then
    echo -e "\nFiled parsing options.\n" ; exit 1
fi

IFS="$(printf '\r')"
VID_DIR="Videos" #(assuming that this directory is in your $HOME location)
eval set -- "$OPTS"

while true; do
    case "$1" in
        -l | --link ) LINKS="${LINKS}${2}$IFS"; shift 2;;
        -r | --room ) ROOM="$2"; shift 2;;
        -a | --upload-as) ASS="${ASS}${2}$IFS"; shift 2;;
        -d | --dir) VID_DIR="$2"; shift 2;;
        -o | --audio-only) A_ONLY="true"; shift ;;
        -y | --yes) YES="true"; shift;;
        --) shift;
            until [[ -z "$1" ]]; do
                LINKS="${LINKS}${1}$IFS" ; shift
            done ; break ;;
        * ) shift ;;
    esac
done

ask_remove() {
    echo -e "Do you want to keep \033[1m$(basename "$1")\033[22m?"
    echo -e "Fille will be moved to \033[1m$HOME/$VID_DIR\033[22m\n"
    while true; do
        printf "\033[32m[Y]es\033[0m/\033[31m[N]o\033[0m) " ; read -r yn
        case "$yn" in
            [Yy]*  ) mv "$1" "$HOME/$VID_DIR" ; break;;
            [Nn]*  ) break ;;
            * )  continue ;;
        esac
    done
}

cleanup() {
    cd "$HOME/$VID_DIR" || exit
    for d in $DIR_LIST ; do
        rm -rf "$d"
    done
    exit
}

postVid() {
    local room="$1"
    cd "$HOME/$VID_DIR" || exit
    for l in $LINKS ; do
        local dir=".tmp_${RANDOM}${RANDOM}"
        DIR_LIST="${DIR_LIST}${dir}$IFS"
        mkdir -p "$dir"
        cd "$dir" || cleanup
        echo -e "\n\033[32m<v> Downloading to \033[1m$HOME/$VID_DIR/$dir\033[22m\n"
        printf "\033[33m"
        if [[ $A_ONLY == "true" ]]; then
            local arg="bestaoudio[ext=wav]/bestaudio[ext=mp3]/bestaudio[ext=ogg]/bestaudio"
        else
            local arg="bestvideo[ext=mp4]+bestaudio/best[ext=mp4]/webm"
        fi
        youtube-dl --no-mtime -o "%(title)s.%(ext)s" -f "$arg" "$l" || cleanup
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
    printf "%s" "$ARG_PREP" | xargs -d "$IFS" volaupload.sh -r "$room" || cleanup
    if [[ -z "$YES" ]] ; then
        for f in $FILE_LIST ; do
            ask_remove "$f"
        done
    fi
    cleanup
}

trap cleanup INT

if [[ -z "$LINKS" ]]; then
    echo -e "\nMy dude, comon. You tried to download nothing.\n" ; exit 1
elif [[ ! -d "$HOME/$VID_DIR" ]]; then
    echo -e "\n${HOME}/${VID_DIR}: This isn't a directory my dude! Exiting ...\n" ; exit 1
else
    postVid "$ROOM"
fi
