#!/bin/bash
# Copyright (c) 2018, Julien Seguinot <seguinot@vaw.baug.ethz.ch>
# GNU General Public License v3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)
#
# Assemble image of plane flying over Mt Blanc
#
#    ./test_mblanc.sh --user USER --pass PASS
#    ./test_mblanc.sh --offline

# pass command-line arguments to sentinelflow
sf="../sentinelflow.sh $*"

# Mt Blanc 1920x1080 @10m
$sf --name mblanc \
    --intersect 45.9,7.0 --daterange 20181116..20181116 \
    --tiles 32TLR --extent 328400,5077100,347600,5089900
