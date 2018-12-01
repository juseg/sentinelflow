#!/bin/bash
# Copyright (c) 2016--2018, Julien Seguinot <seguinot@vaw.baug.ethz.ch>
# GNU General Public License v3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
#
# Assemble Kiruna Sentinel-2 animation using Sentinelflow
#
#    ./anim_kiruna.sh --user USER --pass PASS
#    ./anim_kiruna.sh --offline


# Fetch images
# ------------

# pass command-line arguments to sentinelflow
sf="../sentinelflow.sh $*"

# Kiruna 1920x1080 @10m
$sf --name kiruna \
    --intersect 67.9,20.2 --cloudcover 30 --maxrows 100 \
    --tiles 34WDA --extent 458400,7519600,477600,7530400

# select 48 cloud-free frames for animation
selected="
20150816_102023_459_S2A_RGB.jpg 20150822_104035_460_S2A_RGB.jpg
20150911_104038_457_S2A_RGB.jpg 20160402_102020_459_S2A_RGB.jpg
20160418_104023_463_S2A_RGB.jpg 20160428_104026_460_S2A_RGB.jpg
20160508_104027_456_S2A_RGB.jpg 20160816_104025_461_S2A_RGB.jpg
20160905_104021_462_S2A_RGB.jpg 20161019_102031_459_S2A_RGB.jpg
20170304_104015_464_S2A_RGB.jpg 20170324_104016_456_S2A_RGB.jpg
20170417_102023_460_S2A_RGB.jpg 20170503_104024_458_S2A_RGB.jpg
20170523_104025_461_S2A_RGB.jpg 20170612_104023_458_S2A_RGB.jpg
20170706_102022_460_S2A_RGB.jpg 20170711_102023_463_S2B_RGB.jpg
20170905_104015_460_S2B_RGB.jpg 20170907_103021_455_S2A_RGB.jpg
20170927_103018_458_S2A_RGB.jpg 20170930_104019_460_S2A_RGB.jpg
20171020_104048_464_S2A_RGB.jpg 20171029_102121_463_S2B_RGB.jpg
20180219_103046_462_S2B_RGB.jpg 20180221_102033_460_S2A_RGB.jpg
20180222_104035_067_S2B_RGB.jpg 20180224_103018_463_S2A_RGB.jpg
20180314_104014_461_S2B_RGB.jpg 20180316_103018_462_S2A_RGB.jpg
20180318_102016_461_S2B_RGB.jpg 20180323_102021_456_S2A_RGB.jpg
20180417_102021_457_S2B_RGB.jpg 20180418_104023_461_S2A_RGB.jpg
20180508_104025_460_S2A_RGB.jpg 20180510_103020_459_S2B_RGB.jpg
20180517_102021_457_S2B_RGB.jpg 20180525_103024_462_S2A_RGB.jpg
20180617_104021_457_S2A_RGB.jpg 20180701_102024_461_S2A_RGB.jpg
20180702_104021_464_S2B_RGB.jpg 20180712_104020_461_S2B_RGB.jpg
20180716_102021_464_S2B_RGB.jpg 20180729_103019_462_S2B_RGB.jpg
20180909_102020_462_S2A_RGB.jpg 20181009_102020_464_S2A_RGB.jpg
20181010_104018_457_S2B_RGB.jpg 20181024_102102_462_S2B_RGB.jpg"

# add text labels using Imagemagick
mkdir -p animation/kiruna
for frame in $selected
do
    ifile="composite/kiruna/$frame"
    ofile="animation/kiruna/$frame"
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
title="Three years of mining and moving in Kiruna"
author="J. Seguinot, 2018"
version=$(git describe --abbrev=0 --tags)
credit="Contains modified Copernicus Sentinel data (2015–2018).\n"
credit+="Processed with Sentinelflow ($version)."
convert -size 1920x1080 xc:black -font DejaVu-Sans -gravity center \
    -fill '#ffffff' -pointsize 64 -annotate +000-200 "$title" \
    -fill '#cccccc' -pointsize 48 -annotate +000-040 "$author" \
    -gravity west                 -annotate +240+320 "$credit" \
    anim_kiruna.png

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
secs=$((12+2*hold/25))  # duration of main scene in seconds

# prepare filtergraph for main scene
filt="nullsrc=s=1920x1080:d=$secs[n];"   # create fixed duration stream
filt+="[0]minterpolate=8:dup,"          # duplicate consecutive frames
filt+="minterpolate=25:blend,"          # blend consecutive frames
filt+="loop=$hold:1:0,[n]overlay"       # hold first and last frames

# add title and license frames
filt+=",fade=in:0:$fade,fade=out:$((secs*25-fade)):$fade[main];"  # main scene
filt+="[1]fade=in:0:$fade,fade=out:$((2*25-fade)):$fade[head];"  # title frame
filt+="[2]fade=in:0:$fade,fade=out:$((2*25-fade)):$fade[bysa];"  # license
filt+="[head][main][bysa]concat=3" \

# assemble frames and bumpers using ffmpeg
ffmpeg \
    -pattern_type glob -r 4 -i "animation/kiruna/*.jpg" \
    -loop 1 -t 2 -i anim_kiruna.png \
    -loop 1 -t 2 -i anim_ccbysa.png \
    -filter_complex $filt -pix_fmt yuv420p -c:v libx264 \
    anim_kiruna.mp4
