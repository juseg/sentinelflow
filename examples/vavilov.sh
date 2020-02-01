#!/bin/bash
# Copyright (c) 2018--2019, Julien Seguinot <seguinot@vaw.baug.ethz.ch>
# GNU General Public License v3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
#
# Assemble Vavilov Sentinel-2 animation using Sentinelflow
#
#    ./anim_vavilov.sh --user USER --pass PASS
#    ./anim_vavilov.sh --offline
#
# Surge of the Vavilov ice cap https://vimeo.com/000000000 FIXME
#
# Abstract FIXME
#
# Contains Copernicus Sentinel data (2016--2019). Processed with Sentinelflow:
#
#    sentinelflow.sh [...] --intersect 67.9,20.2 --cloudcover 30 --maxrows 99 \
#                          --tiles 34WDA --extent 458400,7519600,477600,7530400


# Fetch images
# ------------

# pass command-line arguments to sentinelflow
sf="../sentinelflow.sh $*"

## Vavilov 1920x1080 @ 20m
$sf --name vavilov \
    --intersect 79.3,94.4 --cloudcover 10 --maxrows 100 \
    --tiles 46XEP --extent 510800,8794200,549200,8815800 --resolution 20

# select 24 cloud-free frames for animation
selected="
20160325_073552_458_S2A_RGB.jpg 20160403_080545_455_S2A_RGB.jpg
20160411_072609_890_S2A_RGB.jpg 20160508_071622_464_S2A_RGB.jpg
20170502_074613_462_S2A_RGB.jpg 20180405_070621_464_S2A_RGB.jpg
20180430_075611_459_S2A_RGB.jpg 20180508_080605_458_S2B_RGB.jpg
20180623_082600_463_S2B_RGB.jpg 20180708_082603_458_S2A_RGB.jpg
20180811_080606_460_S2A_RGB.jpg 20180923_072614_458_S2B_RGB.jpg
20190416_081634_542_S2B_RGB.jpg 20190506_081637_104_S2B_RGB.jpg
20190525_075637_019_S2A_RGB.jpg 20190529_082634_799_S2B_RGB.jpg
20190604_075635_957_S2A_RGB.jpg 20190622_080639_557_S2B_RGB.jpg
20190715_081637_795_S2B_RGB.jpg 20190730_081637_891_S2A_RGB.jpg
20190804_081636_665_S2B_RGB.jpg 20190911_082624_636_S2A_RGB.jpg
20190915_080630_499_S2A_RGB.jpg 20190919_083627_026_S2B_RGB.jpg
"

# add text labels using Imagemagick
mkdir -p animation/vavilov
for frame in $selected
do
    ifile="composite/vavilov/$frame"
    ofile="animation/vavilov/$frame"
    label="${frame:0:4}.${frame:4:2}.${frame:6:2}"
    if [ ! -f $ofile ]
    then
        convert $ifile -fill '#ffffff80' -draw 'rectangle 1600,40,1880,120' \
                -font DejaVu-Sans-Bold -pointsize 36 -gravity northeast \
                -fill black -annotate +65+60 $label $ofile
    fi
done


# Assemble video
# --------------

# fetch cc by sa icons and replace colors
for icon in cc by sa
do
    if [ ! -f $icon.png ]
    then
        wget -nc https://mirrors.creativecommons.org/presskit/icons/$icon.svg
        sed -e 's/FFFFFF/000000/' \
            -e 's/path /path fill="#bfbfbf" d=/' $icon.svg > $icon.grey.svg
        inkscape $icon.grey.svg -w 320 -h 320 --export-png="$icon.png"
        rm $icon.grey.svg
    fi
done

# prepare title frame
title="The surge of the Vavilov ice cap"
author="J. Seguinot, 2019"
version=$(git describe --abbrev=0 --tags)
credit="Contains modified Copernicus Sentinel data (2016–2018).\n"
credit+="Processed with Sentinelflow ($version)."
convert -size 1920x1080 xc:black -font DejaVu-Sans -gravity center \
    -fill '#ffffff' -pointsize 64 -annotate +000-200 "$title" \
    -fill '#cccccc' -pointsize 48 -annotate +000-040 "$author" \
    -gravity west                 -annotate +240+320 "$credit" \
    anim_vavilov.png

# prepare license frame
convert -size 1920x1080 xc:black -gravity center \
    cc.png -geometry 320x320-400-160 -composite \
    by.png -geometry 320x320+000-160 -composite \
    sa.png -geometry 320x320+400-160 -composite \
    -fill '#bfbfbf' -pointsize 48 \
    -font DejaVu-Sans -annotate +000+160 \
        "This work is licensed under" \
    -font DejaVu-Sans-Bold -annotate +000+280 \
        "http://creativecommons.org/licenses/by-sa/4.0/ " \
    anim_ccbysa.png

# assembling parametres
fade=12  # number of frames for fade in and fade out effects
hold=25  # number of frames to hold in the beginning and end
secs=$((6+2*hold/25))  # duration of main scene in seconds

# prepare filtergraph for main scene
filt="nullsrc=s=1920x1080:d=$secs[n];"  # create fixed duration stream
#filt+="[0]framerate=25:64:191:100"       # blend consecutive frames
filt+="[0]minterpolate=8:dup"          # duplicate consecutive frames
filt+=",minterpolate=25:blend"          # blend consecutive frames
filt+=",loop=$hold:1:0,[n]overlay"          # hold first and last frames

# add title and license frames
filt+=",fade=in:0:$fade,fade=out:$((secs*25-fade)):$fade[main];"  # main scene
filt+="[1]fade=in:0:$fade,fade=out:$((2*25-fade)):$fade[head];"  # title frame
filt+="[2]fade=in:0:$fade,fade=out:$((2*25-fade)):$fade[bysa];"  # license
filt+="[head][main][bysa]concat=3" \

# assemble frames and bumpers using ffmpeg
ffmpeg \
    -pattern_type glob -r 4 -i "animation/vavilov/*.jpg" \
    -loop 1 -t 2 -i anim_vavilov.png \
    -loop 1 -t 2 -i anim_ccbysa.png \
    -filter_complex $filt -pix_fmt yuv420p -c:v libx264 -r 25 \
    anim_vavilov.mp4
