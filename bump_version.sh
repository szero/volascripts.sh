#!/usr/bin/env bash

# script to update version of certain script in script iself, readme and install script
# first argument is script relative path, second is major and third is minor version number

set -euo pipefail
IFS=$'\n\t'

look_after="$1"
readme="./README.md"
install="./install.sh"

bump_readme() {
    sed -i -r "$(sed -n "/$1\\s*ver\\./=" "$readme")s/^($1\\s*ver\\.).*$/\\1 $2\\.$3/" "$readme"
}

bump_install() {
    local name
    name="$(echo "$1" | tr '[:lower:]' '[:upper:]')"
    name="$(echo "$name" | sed 'y/./_/')"
    name="${name}_VER="
    sed -i -r "$(sed -n "/${name}/=" "$install")s/^(${name}).*$/\\1\\($2 $3\\)/" "$install"
}

bump_script() {
    local name
    name="$(echo "$1" | tr '[:lower:]' '[:upper:]')"
    name="$(echo "$name" | tr -d '.')"
    name="__${name}_VERSION__="
    sed -i -r "$(sed -n "/$name/=" "$1")s/^($name).*$/\\1$2\\.$3/" "$1"
}

bump_readme "$look_after" "$2" "$3"
bump_install "$look_after" "$2" "$3"
bump_script "$look_after" "$2" "$3"
