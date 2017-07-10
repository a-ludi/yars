yars
====

This script makes incremental or full backups of a given folder using rsync.


Installion
----------

Just clone the repo or download [the script](./blob/master/yars) to your
computer. Make sure it is executable (`chmod +x yars`) and execute the script

```sh
./yars exmaples/simple.yars
```


Usage
-----


```
USAGE $(basename "$0") [-fdsqhv] [FILE]

    -f, --full              Run a full backup (instead of incremental)
    -d, --delete-only       Just delete backups to meet magnitude requirements
    -s, --suppress-clutter  Delete backup if no changes were detected
    -q, --quiet             Suppress output except for errors
    -v, --version           Display version number, copyright info and exit
    -h, --help, --usage     Display this help and exit

Configure this script to match your own needs by:

  - providing a configuration FILE,
  - by setting the appropriate environment variables
```


### Config Files

You may specify the following options in a seperate file in bash syntax.

`SOURCES=()` – Specify folder(s) to make a backup of. If you want to backup
  only the contents of a folder you have to precede it with a
  blackslash (`/`); otherwise the folder itself will be copied.

`DESTINATION=''` – This is the destination folder. It can be any local or
  remote folder (only ssh supported). Make sure it exists and you have write
  permissions. For each backup a subfolder named 'YYYY-mm-dd-MM-HH-SS' will be
  created. If the creation fails the script will exit with a non-zero status.

`EXCLUDE=''` – Exclude file patterns from the backup (see --exclude option
  from rsync). You may specify multiple patterns separated by colons (':').
  (_TODO use exclude file instead_)

`RSYNC_OPTIONS='-ah --delete'` – This provides a way to control rsync. This
  OVERRIDES the default options. See `man rsync` for details on the options.
  The default options have these explanations:

    -a                 archive mode; equals -rlptgoD (no -H,-A,-X)
    -h                 output numbers in a human-readable format
    --delete           delete extraneous files from dest dirs

`LOG=''` – If a log file is given a new line for each run will be generated;
  unless the call results in the help or version being shown.

The following options control the magnitude of the overall backup. Magnitude
relates to number or age. All deletion takes place AFTER the current backup
unless the `--delete-only` options is present.

`KEEP_NUM=0` – If you set this option to a positive integer only that much
  backups will be kept -- oldest are deleted first.
  (_TODO make a adaptive history, eg: last 60 min, last 24 h, last 30 d, …)

`KEEP_AFTER=''` – If you set this option to a to some abitrary date only
  backups newer than that date will be kept; if the date lies in the future
  nothing is deleted and a warning is issued. The date string must be
  understood by `date --date=STRING`, eg `3 months ago`. Refer to `man date`
  and `info coreutils 'date input formats'` for details.


### Opertional Hooks

You may use these operational hooks to influence the behaviour of the script.
To use the hooks just define a shell function in your config file, eg.

```sh
function after_deletion {
    echo 'current list of backups:' && ls
}
```

`before_init`, `after_init` – the init procedure which sets all the required
  variables and creates the destination folder.

`before_sync` – is called before any rsync action is run; if
  `--suppress-clutter` is active then a dry run will happen immediately after
  this and before the next hook.

`before_copy`, `after_copy ${RSYNC_STATUS}` – rsync does its job

`after_sync` – see above

`before_deletion`, `after_deletion` – this section runs the clean up
  controlled by `KEEP_NUM` and `KEEP_AFTER`; the hooks are called in any case.


License
=======

Copyright (c) 2017 Arne Ludwig <arne.ludwig@posteo.de>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
