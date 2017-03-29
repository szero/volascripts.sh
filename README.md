volaupload.sh
=============

This is a bash script that allows you to upload files to [Volafile](https://volafile.io) 
without using the browser. This is convenient, since it allows you to upload
files with different names without a need to rename them beforehand.
Use -h or --help command for full list of capabilities.

Disclaimer
----------

Script was originally made by [lain](https://github.com/laino) and Xiao. It seemed
to be abandoned so I enhanced it with agrument parsing and some other features.

Prerequsites
------------

- bash >= 4.0
- curl >= 7.33.0

Installation
------------
To install on all UNIX-like systems for all users, type:

    sudo wget https://raw.githubusercontent.com/Szero/volaupload.sh/master/volaupload.sh -O /usr/local/bin/volaupload
    sudo chmod a+rx /usr/local/bin/volaupload

OR

    sudo curl -L https://raw.githubusercontent.com/Szero/volaupload.sh/master/volaupload.sh -o /usr/local/bin/volaupload
    sudo chmod a+rx /usr/local/bin/volaupload

Example usage
-------------

`./volaupload.sh -r BEEPi -n Monkey -u ~/Pictures/wild_nigra.jpg -a "merc - approximation"`

Contributing
------------

Just hit me with that sweet issue ticket or pull-request.
