#!/bin/sh

/usr/bin/xrandr --output eDP1 --off \
                --output DP1 --off \
                --output DP2 --off \
                --output HDMI1 --primary --mode 2560x1440 --pos 0x0 --rotate normal --dpi 108 \
                --output HDMI2 --off \
                --output VIRTUAL1 --off

