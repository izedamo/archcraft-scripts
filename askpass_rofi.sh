#!/usr/bin/env bash

## rofi dir
DIR="$HOME/.config/rofi/dialogs"

rofi -dmenu\
     -password\
     -i\
     -no-fixed-num-lines\
     -p "Root Password: "\
     -theme "$DIR"/askpass.rasi
