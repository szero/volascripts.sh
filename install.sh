#!/usr/bin/env bash

IFS=""

add_path() {
if ! [[ $PATH =~ $2 ]]; then
    echo -e "\nAdding $1 to your PATH ..."
    rc="$HOME/.$(basename "$SHELL")rc"
    echo -e "export PATH=\"$PATH:$1\"" >> "$rc"
fi
}

installing() {
    if [[ -z "$(which youtube-dl)" ]] ; then
        echo -e "\nyoutube-dl wasn't detected, installing ...\n"
        curl --progress-bar -L "https://yt-dl.org/downloads/latest/youtube-dl" -o "$1/youtube-dl"
        chmod a+rx "$1/youtube-dl"
    fi
    if [[ "$(bash --version | head -qn1 | cut -d' ' -f4 | cut -d'.' -f2)" -ge 3 ]]; then
        if [[ -z "$(which curlbar)" ]] ; then
            echo -e "\ncurlbar wasn't detected, installing ...\n"
            curl --progress-bar -L "https://gist.githubusercontent.com/Szero/cd496ca43df4b871df75818ebcc40233/raw/c374e84bacedb1cd10c25bdae9b67ee4a8ef0691/curlbar" -o "$1/curlbar"
            chmod a+rx "$1/youtube-dl"
        fi
    else
        echo -e "\nYour bash version is incompatible with curlbar. Please install bash 4.3 or higher in order to use it.\n"
    fi

    echo -e "\nInstalling volaupload.sh ...\n"
    curl --progress-bar -L "https://rawgit.com/Szero/volascripts.sh/master/volaupload.sh" -o "$1/volaupload.sh"
    chmod a+rx "$1/volaupload.sh"

    echo -e "\nInstalling stuff2vola.sh ...\n"
    curl --progress-bar -L "https://rawgit.com/Szero/volascripts.sh/master/stuff2vola.sh" -o "$1/stuff2vola.sh"
    chmod a+rx "$1/vid2vola.sh"
}

if [[ $UID -ne 0 ]]; then
    echo -e "\nInstalling volascripts locally (for current user) ..."
    dir="$HOME/.local/bin"
    regex="$HOME/\.local/bin"
else
    echo -e "\nInstalling volascripts globally (for all users) ..."
    dir="/usr/local/bin"
    regex=$dir
fi

mkdir -p "$dir"
installing "$dir"
add_path "$dir" "$regex"
echo -e "\nAll done!"
