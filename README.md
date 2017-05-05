volascripts.sh
==============

Those are bash scripts which are meant to interact with [Volafile](https://volafile.org) without
a need of using the browser. I have only two right now but I'm open for suggestions.

volaupload.sh
-------------

This script allows you to upload files to [Volafile](https://volafile.org)
without using the browser. This is convenient, since it allows you to upload
files with different names without a need to rename them beforehand.
Use -h or --help command for full list of capabilities. Check insides of this script
for information on how to preset your room, nick and password.

stuff2vola.sh (vid2vola.sh before)
-------------------------------

Are you a fan of redundancy and don't want to post links to stuff in a chat like a pleb?
Than this is a script for you. It will download most content from the web and upload it to
designeted Volafile room. Script can take multiple arguments just like volaupload.sh.
Script will ask you if you want to keep each of downloaded files if you specify -d option.
To not preserve any of the downloaded files just dont set the -d option.
Invoke script with -h or --help command to list other options. 

Disclaimer
----------

`volaupload.sh` was originally made by [lain](https://github.com/laino) and Xiao. It seemed
to be abandoned so I enhanced it with agrument parsing and some other features.

Prerequsites
------------

- bash >= 4.0 (4.3 version is needed if you want to have better upload bar in volaupload.sh)
- coreutils
- [curl](https://curl.haxx.se/download.html) >= 7.33.0
- [youtube-dl](https://github.com/rg3/youtube-dl)
- [ffmpeg](http://ffmpeg.org/download.html)
- [curlbar](https://gist.github.com/Szero/cd496ca43df4b871df75818ebcc40233) 
    * (required for riced upload bar)

### Optional:

- [inotify-tools](https://github.com/rvoicilas/inotify-tools/wiki)
    * This one is needed just to use --watch command in volaupload.sh script.
      Check the script source and decide if you find this usefull.
        
Installation & Updating
-----------------------

bash and coreutils packages are essential on most Linux distributions, so you should already have
them. All you need to do is to get `curl` and `ffmpeg` with your distribution's package manager.
(`ffmpeg` is needed because sometimes to get best audio and video `youtube-dl` will download 
separate streams and mux them together with `ffmpeg`)
[youtube-dl](https://github.com/rg3/youtube-dl) and
[curlbar](https://gist.github.com/Szero/cd496ca43df4b871df75818ebcc40233) will be 
installed with install script if you don't have them already.

To install on all UNIX-like systems for current user (into `~/.local/bin` directory) type:

    curl -sLo- https://rawgit.com/Szero/volascripts.sh/master/install.sh | bash

To install on all UNIX-like systems for all users (into `/usr/local/bin` directory) type:

    curl -sLo- https://rawgit.com/Szero/volascripts.sh/master/install.sh | sudo bash

Restart your terminal to finalize installation process.
Install script is responsible both for updating and installing so you are good with running it
whenever I release new updates.

Example usage
-------------

    volaupload.sh -r BEEPi -n Monkey -u ~/Pictures/wild_nigra.jpg -a "merc - approximation"

    stuff2vola.sh -r HF33Go -a "oy vey" -l https://jewtube.com/watch?v=SH4L0M

Contributing
------------

Just hit me with that sweet issue ticket or pull-request.
