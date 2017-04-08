volascripts.sh
==============

Those are bash scripts which are meant to interact with [Volafile](https://volafile.io) without
a need of using the browser. I have only two right now but I'm open for suggestions.

volaupload.sh
-------------

This script allows you to upload files to [Volafile](https://volafile.io)
without using the browser. This is convenient, since it allows you to upload
files with different names without a need to rename them beforehand.
Use -h or --help command for full list of capabilities.

vid2vola.sh
-----------

With this badboy you are able to download any videos from the web and upload them directly
to your desired Vola room. Script can take multiple arguments just like volaupload.sh.
By default the script will ask you if you want to keep each of downloaded videos.
To not preserve any of the downloaded videos use -p or --purge option.


Disclaimer
----------

`volaupload.sh` was originally made by [lain](https://github.com/laino) and Xiao. It seemed
to be abandoned so I enhanced it with agrument parsing and some other features.

Prerequsites
------------

- bash >= 4.0
- coreutils
- curl >= 7.33.0
- youtube-dl
- ffmpeg

Installation
------------

bash and coreutils packages are essential on most Linux distributions, so you should already have
them. All you need to do is to get `curl` and `ffmpeg` (ffmpeg is needed because sometimes to get
best audio and video with `youtube-dl` will download separate streams and mux them together) with
your distribution's package manager or by installing them directly from
[curl](https://curl.haxx.se/download.html) and [ffmpeg](http://ffmpeg.org/download.html) websites.
[youtube-dl](https://github.com/rg3/youtube-dl) will be installed with install script if you don't
have it already.

To install on all UNIX-like systems for current user (into `~/.local/bin` directory) type:

    curl -Lo- https://rawgit.com/Szero/volascripts.sh/master/install.sh | bash

To install on all UNIX-like systems for all users (into `/usr/local/bin` directory) type:

    curl -Lo- https://rawgit.com/Szero/volascripts.sh/master/install.sh | sudo bash

Restart your terminal to finalize installation process.

Example usage
-------------

    volaupload.sh -r BEEPi -n Monkey -u ~/Pictures/wild_nigra.jpg -a "merc - approximation"

    vid2vola.sh -r HF33Go -a "oy vey" -u https://jewtube.com/watch?v=SH4L0M

Contributing
------------

Just hit me with that sweet issue ticket or pull-request.
