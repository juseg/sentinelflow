#!/bin/bash
# Copyright (c) 2018--2020, Julien Seguinot <seguinot@vaw.baug.ethz.ch>
# GNU General Public License v3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
#
# Assemble Vavilov Glacier surge animation using Sentinelflow
#
#    ./vavilov.sh --user USER --pass PASS
#    ./vavilov.sh --offline


# Fetch images
# ------------

# Vavilov 1920x1080 @ 40m
sentinelflow.sh $* \
    --intersect 79.3,94.4 --cloudcover 10 --maxrows 99 --tiles 46XEP \
    --extent 510800,8794200,549200,8815800 --resolution 20 --name vavilov

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
    credit="CC BY-SA 4.0 J. Seguinot (2020). \
Contains modified Copernicus Sentinel data. Processed with SentinelFlow."
    if [ -f $ifile ] && [ ! -f $ofile ]
    then
        convert $ifile -crop 1440x960+240+80 +repage \
                -fill '#ffffff80' -draw 'rectangle 48,48,384,136' \
                -font Bitstream-Vera-Sans-Bold -pointsize 48 -gravity northwest \
                -fill black -annotate +64+64 $label \
                -fill '#ffffff80' -draw 'rectangle 0,912,1440,960' \
                -font Bitstream-Vera-Sans -pointsize 24 -gravity southeast \
                -fill black -annotate +8+8 "$credit" $ofile
    fi
done


# Assemble animation
# ------------------

# animated gif
convert -delay 10 animation/vavilov/*.jpg -delay 160 $ofile \
        -loop 0 -resize 50% vavilov.gif

# mp4 video
ffmpeg -pattern_type glob -r 10 -i "animation/vavilov/*.jpg" \
    -filter_complex "nullsrc=s=1440x960:d=4:r=10,[0]overlay" \
    -pix_fmt yuv420p -c:v libx264 vavilov.mp4
