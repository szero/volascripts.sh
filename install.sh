#!/usr/bin/env bash

if [[ $UID -ne 0 ]]; then
    echo -e "\nYou have to be root in order to install volascripts.sh"; exit 1
fi

if ! [[ $(whereis -b youtube-dl | cut -d':' -f2) ]] ; then
    echo -e "\nyoutube-dl wasn't detected, installing ...\n"
    curl -#L "https://yt-dl.org/downloads/latest/youtube-dl" -o "/usr/local/bin/youtube-dl"
    chmod a+rx /usr/local/bin/youtube-dl
fi

echo -e "\ninstalling volaupload.sh ...\n"
curl -#L "https://rawgit.com/Szero/volascripts.sh/master/volaupload.sh" -o "/usr/local/bin/volaupload.sh"
chmod a+rx "/usr/local/bin/volaupload.sh"

echo -e "\nInstalling volaupload.sh ...\n"
curl -#L "https://rawgit.com/Szero/volascripts.sh/master/vid2vola.sh" -o "/usr/local/bin/vid2vola.sh"
chmod a+rx "/usr/local/bin/vid2vola.sh"

echo -e "\nAll done!"
