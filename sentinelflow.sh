#!/bin/bash
# Copyright (c) 2016--2018, Julien Seguinot <seguinot@vaw.baug.ethz.ch>
# GNU General Public License v3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)


# Command-line help
# -----------------

helpstring="Usage: sentinelflow.sh --user USERNAME --pass PASSWORD [options]

Automated satellite image workflow for Sentinel-2.

General options
    -h, --help          display this help message and exit
    -u, --user          username at Copernicus Open Access Hub (required)
    -p, --pass          password at Copernicus Open Access Hub (required)
    -w, --workdir       working directory (default: current)

Query and download options
    -c, --cloudcover    maximum cloud cover fraction (default: none)
    -d, --daterange     range of sensing date in query (default: none)
    -i, --intersect     point LAT,LON or rectangle W,E,S,N (default: none)
    -m, --maxrows       maximum number of rows in query (default: 10)
    -t, --tiles         tiles to download, comma-separated (default: 32TMS)

Image composition options
    -b, --bands         color bands (IRG, RGB) for composition (default: RGB)
    -e, --extent        W,S,E,N extent in local UTM coordinates (default: none)
    -n, --name          region name for composite images (default: none)
    -r, --resolution    spatial resolution in meters (default: none)
    -s, --sigma         sigmoidal contrast parameters (default: 15,50%)
    -x, --nullvalues    maximum percentage of null values (default: 50)

Flags
    -1, --sentinel1     download sentinel-1 data (experimental, default: no)
    -f, --fetchonly     download data only, do not patch images (default: no)
    -k, --keeptiff      keep intermediate TIFF images (default: no)
    -o, --offline       offline mode, use local data only (default: no)

Sentinelflow (c) 2016--2018 Julien Seguinot <seguinot@vaw.baug.ethz.ch>
Please contact the author before using images in publications.
Report bugs at: <https://github.com/juseg/sentinelflow>."


# Parse command-line arguments
# ----------------------------

# loop on keyword, argument pairs
while [[ $# -gt 0 ]]
do
    case "$1" in

        # general options
        -u|--user)
            user="$2"
            shift
            ;;
        -p|--pass)
            pass="$2"
            shift
            ;;
        -w|--workdir)
            workdir="$2"
            shift
            ;;

        # query and download options
        -c|--cloudcover)
            cloudcover="$2"
            shift
            ;;
        -d|--daterange)
            daterange="$2"
            shift
            ;;
        -i|--intersect)
            intersect="$2"
            shift
            ;;
        -m|--maxrows)
            maxrows="$2"
            shift
            ;;
        -t|--tiles)
            tiles="$2"
            shift
            ;;

        # compose and convert options
        -b|--bands)
            bands="$2"
            shift
            ;;
        -e|--extent)
            extent="$2"
            shift
            ;;
        -n|--name)
            region="$2"
            shift
            ;;
        -r|--resolution)
            resolution="$2"
            shift
            ;;
        -s|--sigma)
            sigma="$2"
            shift
            ;;
        -x|--nullvalues)
            nullvalues="$2"
            shift
            ;;

        # flags
        -1|--sentinel1)
            sentinel1="yes"
            ;;
        -f|--fetchonly)
            fetchonly="yes"
            ;;
        -h|--help)
            echo "$helpstring"
            exit 0
            ;;
        -k|--keeptiff)
            keeptiff="yes"
            ;;
        -o|--offline)
            offline="yes"
            ;;

        # unknown option
        *)
            echo "Unknown option $1. Exiting."
            exit 2
            ;;

    esac
    shift
done

# default working directory
workdir=${workdir:="."}

# default query and download options
cloudcover=${cloudcover:=""}
daterange=${daterange:=""}
intersect=${intersect:=""}
maxrows=${maxrows:="10"}
tiles=${tiles:=""}

# default compose and convert options
bands=${bands:="RGB"}
extent=${extent:=""}
region=${region:="t$(echo $tiles | tr '[:upper:]' '[:lower:]' | tr ',' 't')"}
resolution=${resolution:=""}
sigma=${sigma:="15,50%"}
nullvalues=${nullvalues:="50"}

# default flags
sentinel1=${sentinel1:="no"}
fetchonly=${fetchonly:="no"}
keeptiff=${keeptiff:="no"}
offline=${offline:="no"}


# Check dependencies
# ------------------

# check for ImageMagick
if ! [ -x "$(command -v convert)" ]
then
    echo "Error: convert not found. Please install ImageMagick." >&2
    exit 1
fi

# check for GDAL binaries
if ! [ -x "$(command -v gdalbuildvrt)" ]
then
    echo "Error: gdalbuildvrt not found. Please install GDAL binaries." >&2
    exit 1
fi
if ! [ -x "$(command -v gdal_translate)" ]
then
    echo "Error: gdal_translate not found. Please install GDAL binaries." >&2
    exit 1
fi

# check for XMLStarlet
xmlexec="$(command -v xmlstarlet || command -v xml)"
if ! [ -x "$xmlexec" ]
then
    echo "Error: xml or xmlstarlet not found. Please install XMLStarlet." >&2
    exit 1
fi


# Download requested tiles
# ------------------------

# change to input work directory
cd $workdir

# if not in offline mode
if [ "$offline" != "yes" ]
then

    # check for compulsory arguments
    if [ -z "$user" ]
    then
        echo "Please provide Copernicus user name (--user)" \
             "or run offline (--offline)."
        exit 2
    fi
    if [ -z "$pass" ]
    then
        echo "Please provide Copernicus pass word (--pass)" \
             "or run offline (--offline)."
        exit 2
    fi

    # parse intersect if list of four numbers
    if [[ "$intersect" =~ ^[\-0-9.]*,[\-0-9.]*,[\-0-9.]*,[\-0-9.]*$ ]]
    then
        read w s e n <<< $(echo "$intersect" | tr ',' ' ')
        intersect="POLYGON(($w $s,$e $s,$e $n,$w $n,$w $s))"
    fi

    # construct query
    if [ "$sentinel1" == "yes" ]
    then
        query="platformname:Sentinel-1 AND producttype:GRD"
        query+=" AND polarisationmode:HH+HV AND sensoroperationalmode:IW"
    else
        query="platformname:Sentinel-2 AND producttype:S2MSI1C"
    fi
    [ -n "$intersect" ] && query+=" AND footprint:\"intersects(${intersect})\""
    [ -n "$cloudcover" ] && query+=" AND cloudcoverpercentage:[0 TO ${cloudcover}]"

    # apply date bounds if provided
    if [ "$daterange" != "" ]
    then
        d0=${daterange%%..*}
        d1=${daterange##*..}
        d0=${d0:0:4}-${d0:4:2}-${d0:6:2}T00:00:00.000Z
        d1=${d1:0:4}-${d1:4:2}-${d1:6:2}T59:59:59.999Z
        query+=" AND beginPosition:[$d0 TO $d1]"
        query+=" AND endPosition:[$d0 TO $d1]"
    fi

    # search for products and save to searchresults.xml
    url="https://scihub.copernicus.eu/dhus/search?q=${query}&rows=${maxrows}"
    wget --quiet --no-check-certificate --user=${user} --password=${pass} \
         --output-document searchresults.xml "$url"

    # if valid xml search results then parse them and loop on products
    if $xmlexec -q val searchresults.xml
    then
        $xmlexec sel -t -m "//_:entry" -v "_:title" -o " " \
                -m "_:link" -i 'not(@rel)' -v "@href" -n searchresults.xml |
        while read name urlbase
        do

            # break url to include invidual nodes
            name=${name}.SAFE
            urlbase=${urlbase%/\$value}

            # download manifest file if missing
            manifestpath="manifests/$name"
            url="${urlbase}/Nodes('${name}')/Nodes('manifest.safe')/\$value"
            if [ ! -s "$manifestpath" ]
            then
                echo "Downloading file $(basename ${manifestpath})..."
                mkdir -p $(dirname $manifestpath)
                wget --quiet --no-check-certificate --continue \
                     --user=${user} --password=${pass} \
                     --output-document $manifestpath $url
            fi

            # manifest file name pattern
            if [ "$sentinel1" == "yes" ]
            then
                pattern="hh.*tiff"
            else
                case ${bands,,} in
                    irg) bandnumbers="3|4|8" ;;
                    rgb) bandnumbers="2|3|4" ;;
                    *)   echo "Error, unsupported color mode $bands" ;;
                esac
                pattern="T(${tiles//,/|}).*(MTD.*.xml|_B0($bandnumbers).jp2)"
            fi

            # find and loop on granule xml files and bands for requested tiles
            $xmlexec sel -t -m "//fileLocation" -v "@href" -n $manifestpath |
            egrep -e "$pattern" | while read line
            do

                # get file path and remote url
                filepath=${line##./}
                destpath=${line/GRANULE/granules}
                nodepath=$(sed -e "s_/_')/Nodes('_g" <<< "${name}/${filepath}")
                nodepath="Nodes('${nodepath}')"
                url="${urlbase}/${nodepath}/\$value"

                # download files if missing
                if [ ! -s $destpath ]
                then
                    echo "Downloading file $(basename ${destpath})..."
                    mkdir -p $(dirname $destpath)
                    wget --quiet --no-check-certificate --continue \
                         --user=${user} --password=${pass} \
                         --output-document $destpath $url
                fi

            done

        done

    # warn about invalid xml query results
    else
        echo "Failed query, continuing offline."
    fi

fi

# if download only mode
if [ "$fetchonly" == "yes" ] || [ "$sentinel1" == "yes" ]
then
    exit 0
fi

# if no tiles were provided
if [ "$tiles" == "" ]
then
    echo "No tiles were provided. Exiting."
    exit 0
fi


# Prepare scene VRTs by sensing date
# ----------------------------------

mkdir -p scenes

# for each tile
for tile in ${tiles//,/ }
do

    # loop on available data packages
    find granules -maxdepth 1 -path "*T${tile}*" | while read datadir
    do

        # find granule name
        granule=$(basename $datadir)
        granule=${granule%_N02.0?}

        # find sensing date and convert format
        #namedate=${granule:25:15}  # !! this is not the sensing date
        sensdate=$($xmlexec sel -t -v "//SENSING_TIME" $datadir/*.xml)
        sensdate=$(date -u -d$sensdate +%Y%m%d_%H%M%S_%3N)

        # find satellite prefix
        tid=$($xmlexec sel -t -v "//TILE_ID" $datadir/*.xml)
        sat=${tid:0:3}

        # on error, assume xml file is broken and remove it
        if [ "$?" -ne "0" ]
        then
            echo "Error, removing $datadir/*.xml ..."
            rm $datadir/*.xml
            continue
        fi

        # build scene VRT
        ofile="scenes/T${tile}/${sensdate}_${sat}_${bands^^}.vrt"
        if [ ! -s $ofile ]
        then
            echo "Building $ofile ..."
            mkdir -p $(dirname $ofile)
            case ${bands,,} in
                irg) gdalbuildvrt -separate -srcnodata 0 -q $ofile \
                     $datadir/IMG_DATA/*_B0{8,4,3}.jp2
                     exit_code="$?"
                     ;;
                rgb) gdalbuildvrt -separate -srcnodata 0 -q $ofile \
                     $datadir/IMG_DATA/*_B0{4,3,2}.jp2
                     exit_code="$?"
                     ;;
                *)   echo "Error, unsupported color mode $bands"
                     exit 1
                     ;;
            esac
            if [ "$exit_code" -ne "0" ]
            then
                echo "Error, removing $ofile ..."
                rm $ofile
                continue
            fi
        fi

    done

done


# Export composite images by region
# ---------------------------------

# make output directories
mkdir -p composite/$region

# parse extent for world file
ewres="$resolution"
nsres="$resolution"
w=$(echo "$extent" | cut -d ',' -f 1)
n=$(echo "$extent" | cut -d ',' -f 4)
worldfile="${ewres}\n0\n-0\n-${nsres}\n${w}\n${n}"

# find sensing dates (and sat) with data on requested tiles
allscenes=$(find scenes | egrep "T(${tiles//,/|})/" || echo "")
sensdates=$(echo "$allscenes" | sed 's:.*/::' | cut -d '_' -f 1-4 | uniq)

# loop on sensing dates
for sensdate in $sensdates
do

    # skip date if image or text file is already here
    ofile="composite/$region/${sensdate}_${bands^^}"
    [ -s $ofile.jpg ] || [ -s $ofile.txt ] && continue

    # find how many scenes correspond to requested tiles over region
    scenes=$(find scenes | egrep "T(${tiles//,/|})/${sensdate}_${bands^^}.vrt")
    n=$(echo $scenes | wc -w)

    # assemble mosaic VRT in temporary files
    gdalargs="-q"
    [ -n "$extent" ] && gdalargs+=" -te ${extent//,/ }"
    [ -n "$resolution" ] && gdalargs+=" -tr $resolution $resolution"
    gdalbuildvrt $gdalargs tmp_$$.vrt $scenes

    # export composite over selected region
    if [ ! -s $ofile.tif ]
    then
        echo "Exporting $ofile.tif ..."
        gdal_translate -co "PHOTOMETRIC=rgb" -q tmp_$$.vrt $ofile.tif
        if [ "$?" -ne "0" ]
        then
            echo "Error, removing $ofile.tif ..."
            rm $ofile.tif
            continue
        fi
    fi

    # count percentage of null pixels
    nulls=$(convert -quiet $ofile.tif -fill white +opaque black \
            -print "%[fx:100*(1-mean)]" null:)
    message="Found ${nulls}% null values."
    echo $message

    # if more nulls than allowed, report in txt and remove tifs
    if [ "${nulls%.*}" -ge "${nullvalues}" ]
    then
        echo "Removing $ofile.tif ..."
        echo "$message" > $ofile.txt
        [ -f $ofile.tif ] && rm $ofile.tif
        [ -f $ofile.jpg ] && rm $ofile.jpg
        continue
    fi

    # sharpen only full-resolution images
    if [ "$resolution" == "10" ]
    then
        sharpargs="-unsharp 0x1"
    else
        sharpargs=""
    fi

    # gamma correction depends on color mode
    case ${bands,,} in
        irg) gamma="5.05,5.10,4.85";;
        rgb) gamma="5.50,5.05,5.10";;
    esac

    # convert to human-readable jpeg
    if [ ! -s $ofile.jpg ]
    then
        echo "Converting $ofile.tif ..."
        convert -gamma $gamma -sigmoidal-contrast $sigma \
                -modulate 100,150 $sharpargs -quality 85 -quiet \
                $ofile.tif $ofile.jpg
        echo -e "$worldfile" > $ofile.jpw
    fi

    # remove tiff unless asked not to
    if [ ! "$keeptiff" == "yes" ]
    then
        echo "Removing $ofile.tif ..."
        rm $ofile.tif
    fi

done

# remove temporary mosaic VRT
[ -f tmp_$$.vrt ] && rm tmp_$$.vrt

# happy end
exit 0

