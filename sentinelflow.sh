#!/bin/bash

# Command-line help
# -----------------

helpstring="Usage: sentinelflow.sh --user USERNAME --pass PASSWORD [options]

Search, download and patch Copernicus Sentinel-2A data into color images.
Registration to the Copernicus Open Access Hub is required.
Defaults produce images over Aletsch Glacier in the Alps.

General options
    -h, --help          display this help message and exit
    -u, --user          username at Copernicus Open Access Hub (required)
    -p, --pass          password at Copernicus Open Access Hub (required)
    -w, --workdir       working directory (default: current)

Query and download options
    -c, --cloudcover    maximum cloud cover fraction (default: 100)
    -d, --daterange     range of sensing date in query (default: none)
    -i, --intersect     point LAT,LON or rectangle W,E,S,N (default: 46.5,8.1)
    -m, --maxrows       maximum number of rows in query (default: 10)
    -t, --tiles         tiles to download, comma-separated (default: 32TMS)

Image composition options
    -e, --extent        W,S,E,N extent in local UTM coordinates (default: none)
    -n, --name          region name for composite images (default: none)
    -r, --resolution    spatial resolution in meters (default: none)
    -s, --sigma         sigmoidal contrast parameters (default: 15,50%)
    -x, --nullvalues    maximum percentage of null values (default: 50)

Flags
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
cloudcover=${cloudcover:="100"}
daterange=${daterange:=""}
intersect=${intersect:="46.5,8.1"}
maxrows=${maxrows:="10"}
tiles=${tiles:="32TMS"}

# default compose and convert options
extent=${extent:=""}
region=${region:="t$(echo $tiles | tr '[:upper:]' '[:lower:]' | tr ',' 't')"}
resolution=${resolution:=""}
sigma=${sigma:="15,50%"}
nullvalues=${nullvalues:="50"}

# default flags
fetchonly=${fetchonly:="no"}
keeptiff=${keeptiff:="no"}
offline=${offline:="no"}


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

    # prepare query
    query="producttype:S2MSI1C AND "
    query+="footprint:\"intersects(${intersect})\" AND "
    query+="cloudcoverpercentage:[0 TO ${cloudcover}]"

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
    if xml -q val searchresults.xml
    then
        xml sel -t -m "//_:entry" -v "_:title" -o " " \
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

            # find and loop on granule xml files and bands for requested tiles
            xml sel -t -m "//fileLocation" -v "@href" -n $manifestpath |
            egrep "T(${tiles//,/|})" | egrep "(.xml|_B0(2|3|4|8).jp2)" |
            grep -v "QI_DATA" | while read line
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
if [ "$fetchonly" == "yes" ]
then
    exit 0
fi


# Prepare RGB and IRG scene VRTs by sensing date
# ----------------------------------------------

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
        sensdate=$(xml sel -t -v "//SENSING_TIME" $datadir/*.xml)
        sensdate=$(date -u -d$sensdate +%Y%m%d_%H%M%S_%3N)

        # find satellite prefix
        tid=$(xml sel -t -v "//TILE_ID" $datadir/*.xml)
        sat=${tid:0:3}

        # on error, assume xml file is broken and remove it
        if [ "$?" -ne "0" ]
        then
            echo "Error, removing $datadir/*.xml ..."
            rm $datadir/*.xml
            continue
        fi

        # build RGB VRT
        ofile_rgb="scenes/${sat}_${sensdate}_T${tile}_RGB.vrt"
        if [ ! -s $ofile_rgb ]
        then
            echo "Building scene $(basename $ofile_rgb) ..."
            gdalbuildvrt -separate -srcnodata 0 -q $ofile_rgb \
                $datadir/IMG_DATA/*_B0{4,3,2}.jp2
            if [ "$?" -ne "0" ]
            then
                echo "Error, removing $ofile_rgb ..."
                rm $ofile_rgb
                continue
            fi
        fi

        # build IRG VRT
        ofile_irg="scenes/${sat}_${sensdate}_T${tile}_IRG.vrt"
        if [ ! -s $ofile_irg ]
        then
            echo "Building scene $(basename $ofile_irg) ..."
            gdalbuildvrt -separate -srcnodata 0 -q $ofile_irg \
                $datadir/IMG_DATA/*_B0{8,4,3}.jp2
            if [ "$?" -ne "0" ]
            then
                echo "Error, removing $ofile_irg ..."
                rm $ofile_irg
                continue
            fi
        fi

    done

done


# Export RGB and IRG composite images by region
# ---------------------------------------------

# make output directories
mkdir -p composite/$region/{rgb,irg}

# parse extent for world file
ewres="$resolution"
nsres="$resolution"
w=$(echo "$extent" | cut -d ',' -f 1)
n=$(echo "$extent" | cut -d ',' -f 4)
worldfile="${ewres}\n0\n-0\n-${nsres}\n${w}\n${n}"

# find sensing dates with data on requested tiles
scenes=$(ls scenes | egrep "T(${tiles//,/|})" || echo "")
sensdates=$(echo "$scenes" | cut -c 1-23 | uniq)

# loop on sensing dates
for sensdate in $sensdates
do

    # skip date if both files are already here
    ofile_rgb="composite/$region/rgb/${sensdate}_RGB"
    ofile_irg="composite/$region/irg/${sensdate}_IRG"
    [ -s $ofile_rgb.jpg ] && [ -s $ofile_irg.jpg ] && continue
    [ -s $ofile_rgb.txt ] && [ -s $ofile_irg.txt ] && continue

    # find how many scenes correspond to requested tiles over region
    scenes_rgb=$(find scenes | egrep "${sensdate}_T(${tiles//,/|})_RGB.vrt")
    scenes_irg=$(find scenes | egrep "${sensdate}_T(${tiles//,/|})_IRG.vrt")
    n=$(echo $scenes_rgb | wc -w)

    # assemble mosaic VRT in temporary files
    gdalargs="-q"
    [ -n "$extent" ] && gdalargs+=" -te ${extent//,/ }"
    [ -n "$resolution" ] && gdalargs+=" -tr $resolution $resolution"
    gdalbuildvrt $gdalargs tmp_$$_rgb.vrt $scenes_rgb
    gdalbuildvrt $gdalargs tmp_$$_irg.vrt $scenes_irg

    # export RGB composite over selected region
    if [ ! -s $ofile_rgb.tif ]
    then
        echo "Exporting $ofile_rgb.tif ..."
        gdal_translate -co "PHOTOMETRIC=rgb" -q tmp_$$_rgb.vrt $ofile_rgb.tif
        if [ "$?" -ne "0" ]
        then
            echo "Error, removing $ofile_rgb.tif ..."
            rm $ofile_rgb.tif
            continue
        fi
    fi

    # count percentage of null pixels
    nulls=$(convert -quiet $ofile_rgb.tif -fill white +opaque black \
            -print "%[fx:100*(1-mean)]" null:)
    message="Found ${nulls}% null values."
    echo $message

    # if more nulls than allowed, report in txt and remove tifs
    if [ "${nulls%.*}" -ge "${nullvalues}" ]
    then
        echo "Removing $ofile_rgb.tif ..."
        echo "$message" > $ofile_rgb.txt
        echo "$message" > $ofile_irg.txt
        [ -f $ofile_rgb.tif ] && rm $ofile_rgb.tif
        [ -f $ofile_irg.tif ] && rm $ofile_irg.tif
        [ -f $ofile_rgb.jpg ] && rm $ofile_rgb.jpg
        [ -f $ofile_irg.jpg ] && rm $ofile_irg.jpg
        continue
    fi

    # sharpen only full-resolution images
    if [ "$resolution" == "10" ]
    then
        sharpargs="-unsharp 0x1"
    else
        sharpargs=""
    fi

    # convert to human-readable jpeg
    if [ ! -s $ofile_rgb.jpg ]
    then
        echo "Converting $ofile_rgb.tif ..."
        convert -gamma 5.05,5.10,4.85 -sigmoidal-contrast $sigma \
                -modulate 100,150 $sharpargs -quality 85 -quiet \
                $ofile_rgb.tif $ofile_rgb.jpg
        echo -e "$worldfile" > $ofile_rgb.jpw
    fi

    # remove tiff unless asked not to
    if [ ! "$keeptiff" == "yes" ]
    then
        echo "Removing $ofile_rgb.tif ..."
        rm $ofile_rgb.tif
    fi

    # export IRG composite over selected region
    if [ ! -s $ofile_irg.tif ]
    then
        echo "Exporting $ofile_irg.tif ..."
        gdal_translate -co "PHOTOMETRIC=rgb" -q tmp_$$_irg.vrt $ofile_irg.tif
        if [ "$?" -ne "0" ]
        then
            echo "Error, removing $ofile_irg.tif ..."
            rm $ofile_irg.tif
            continue
        fi
    fi

    # convert to human-readable jpeg
    if [ ! -s $ofile_irg.jpg ]
    then
        echo "Converting $ofile_irg.tif ..."
        convert -gamma 5.50,5.05,5.10 -sigmoidal-contrast $sigma \
                -modulate 100,150 $sharpargs -quality 85 -quiet \
                $ofile_irg.tif $ofile_irg.jpg
        echo -e "$worldfile" > $ofile_irg.jpw
    fi

    # remove tiff unless asked not to
    if [ ! "$keeptiff" == "yes" ]
    then
        echo "Removing $ofile_irg.tif ..."
        rm $ofile_irg.tif
    fi

done

# remove temporary mosaic VRTs
[ -f tmp_$$_rgb.vrt ] && rm tmp_$$_rgb.vrt
[ -f tmp_$$_irg.vrt ] && rm tmp_$$_irg.vrt

# happy end
exit 0

