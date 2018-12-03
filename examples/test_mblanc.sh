#!/bin/bash
# Copyright (c) 2018, Julien Seguinot <seguinot@vaw.baug.ethz.ch>
# GNU General Public License v3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
#
# Assemble image of plane flying over Mt Blanc
#
#    ./test_mblanc.sh --user USER --pass PASS
#    ./test_mblanc.sh --offline
#
# High above the top of Europe https://imaggeo.egu.eu/view/13612
#
# Sentinel-2B imaged the highest mountains of western Europe, just the moment
# an aeroplane was about to fly over the granite peaks of Grandes Jorasses and
# cross the border from France to Italy. The passengers on the right side of
# the plane must have enjoyed a spectacular view on Mont Blanc, just nine
# kilometers away to the south-west, and Mer de Glace, the longest glacier in
# France flowing down from its peak.
#
# Note the shadow of the granite "aiguilles" on fresh early winter snow in the
# upper part of the glacier. The famous Aiguille de Midi is casting its shadow
# on the village of Chamonix on the top-left, as late autumn colours are still
# visible on the larch in Val Ferret in the bottom-right corner of the image.
#
# Contains Copernicus Sentinel data (2018). Processed with Sentinelflow:
#
#   sentinelflow.sh [...] --intersect 45.9,7.0 --daterange 20181116..20181116 \
#                         --tiles 32TLR --extent 328400,5077100,347600,5089900

# pass command-line arguments to sentinelflow
sf="../sentinelflow.sh $*"

# Mt Blanc 1920x1080 @10m
$sf --name mblanc \
    --intersect 45.9,7.0 --daterange 20181116..20181116 \
    --tiles 32TLR --extent 328400,5077100,347600,5089900
