#!/usr/bin/env bash
# shellcheck disable=SC1117

set -uo pipefail
IFS=$'\n\t'

VOLAUPLOAD_SH_VER=(2 7)
STUFF2VOLA_SH_VER=(2 4)
VOLACRYPT_SH_VER=(1 3)
PROWATCH_SH_VER=(1 2)
CURLBAR_VER=(1 2)

add_path() {
if ! [[ $PATH =~ $2 ]]; then
    echo -e "\nAdding $1 to your PATH ..."
    rc="$HOME/.$(basename "$SHELL")rc"
    echo -e "export PATH=\"$PATH:$1\"" >> "$rc"
fi
}

install_stuff() {
    echo -e "\nInstalling $2 ...\n"
    if ! curl --progress-bar -fL "https://raw.githubusercontent.com/szero/volascripts.sh/master/$2" -o "$1/$2" ; then
        echo -e "\nError while fetching $2. Aborting its installation."
    else
        chmod a+rx "$1/$2"
    fi
}

install_curlbar() {
    echo -e "\nInstalling curlbar ...\n"
    if ! curl --progress-bar -fL "https://gist.githubusercontent.com/szero/cd496ca43df4b871df75818ebcc40233/raw/c9f7ce19d0d76e8b20b5e573b7236178b0158f53/curlbar" -o "$1/curlbar" ;then
        echo -e "\nError while fetching curlbar. Aborting its installation."
    else
        chmod a+rx "$1/curlbar"
    fi
}

_check_version() {
    local path_to_script
    # how to make stuff like that portable??
    # is hack with type good enough?
    if ! path_to_script="$(type "$1" 2>/dev/null | cut -d' ' -f3)"; then
        return 1
    fi
    local version
    if version=$(grep -oE "^$2.*" "$path_to_script"); then
        echo -n "$version" | cut -d'=' -f2
        return 0
    fi
    #return 1 if script exists but its without versioning
    return 1
}

version_check() {
    local version
    local -a ver=( "${@:2:4}" )
    local ver_str
    ver_str="__$(echo "$1" | tr -d "." | tr "[:lower:]" "[:upper:]")_VERSION__"
    if version=$(_check_version "$1" "$ver_str"); then
        if [[ $(echo "$version" | cut -d'.' -f1) -ge ${ver[0]} ]] && \
           [[ $(echo "$version" | cut -d'.' -f2) -ge ${ver[1]} ]]; then
            echo -e "\nYour $1 version is up to date!"
            return 0
        fi
    fi
    return 1
}

installing() {
    if ! type bc > /dev/null 2>&1; then
        echo -e "\nbc not detected, stopping installation. Check if its avaliable in"
        echo -e "your package manager, if not please check out readme for more info."; exit 1
    fi
    if ! type youtube-dl > /dev/null 2>&1 ; then
        echo -e "\nyoutube-dl wasn't detected, installing ...\n"
        curl --progress-bar -L "https://yt-dl.org/downloads/latest/youtube-dl" -o "$1/youtube-dl"
        chmod a+rx "$1/youtube-dl"
    fi
    echo -e "\nDo you want to install/update curlbar?"
    echo -e "With curlbar you will have more verbose upload bar in volascripts."
    while true; do
        local yn; printf "\033[32m[Y]es\033[0m/\033[31m[N]o\033[0m) "; read -er yn
        case "$yn" in
            [Yy]*)
            if [[ "${BASH_VERSINFO[0]}" -ge 4 ]] && [[ "${BASH_VERSINFO[1]}" -ge 3 ]]; then
                if ! version_check "curlbar" "${CURLBAR_VER[@]}" ; then
                    install_curlbar "$1"
                fi
            else
                echo -e "\nYour bash version is incompatible with curlbar. Please install bash"
                echo -e "4.3 or higher in order to use it.\n"
            fi; break ;;
            [Nn]*) break ;;
            * )  continue ;;
        esac
    done
    if ! version_check "volaupload.sh" "${VOLAUPLOAD_SH_VER[@]}" ; then
        install_stuff "$1" "volaupload.sh"
    fi
    if ! version_check "stuff2vola.sh" "${STUFF2VOLA_SH_VER[@]}" ; then
        install_stuff "$1" "stuff2vola.sh"
    fi
    if ! version_check "volacrypt.sh" "${VOLACRYPT_SH_VER[@]}" ; then
        install_stuff "$1" "volacrypt.sh"
    fi
    if ! version_check "prowatch.sh" "${PROWATCH_SH_VER[@]}" ; then
        install_stuff "$1" "prowatch.sh"
    fi
}

if [[ $UID -ne 0 ]]; then
    echo -e "\nInstalling volascripts locally (for current user) into ~/.local/bin ..."
    dir="$HOME/.local/bin"
    regex="$HOME/\.local/bin"
else
    echo -e "\nInstalling volascripts globally (for all users) into /usr/local/bin ..."
    dir="/usr/local/bin"
    regex=$dir
fi

mkdir -p "$dir"
installing "$dir"
add_path "$dir" "$regex"
echo -e "\nAll done!"
