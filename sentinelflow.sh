#!/bin/bash

# Download Sentinel-2A data and export RGB and IRG images
# =======================================================
# B02 490nm B
# B03 560nm G
# B04 665nm R
# B08 842nm IR


# Parse command-line arguments
# ----------------------------

# loop on keyword, argument pairs
while [[ $# -gt 0 ]]
do
    case "$1" in

        # general options
        -d|--basedir)
            basedir="$2"
            shift
            ;;
        -u|--user)
            user="$2"
            shift
            ;;
        -p|--pass)
            pass="$2"
            shift
            ;;

        # query options
        -i|--intersect)
            intersect="$2"
            shift
            ;;
        -t|--tiles)
            tiles="$2"
            shift
            ;;
        -c|--cloudcover)
            cloudcover="$2"
            shift
            ;;
        -m|--maxrows)
            maxrows="$2"
            shift
            ;;

        # compose options
        -n|--name)
            region="$2"
            shift
            ;;
        -e|--extent)
            extent="$2"
            shift
            ;;
        -r|--resolution)
            resolution="$2"
            shift
            ;;
        -x|--nullvalues)
            nullvalues="$2"
            shift
            ;;

        # flags
        -o|--offline)
            offline="yes"
            ;;

        # unknown option
        *)
            echo "Unknown option $1. Exiting."
            exit 0
            ;;

    esac
    shift
done

# check for compulsory arguments
if [ -z "$user" ]
then
    echo "Please provide Copernicus user name (--user)."
    exit 2
fi
if [ -z "$pass" ]
then
    echo "Please provide Copernicus password (--pass)."
    exit 2
fi

# base directory
basedir=${basedir:="."}

# intersect lat,lon used in query, comma-separated
intersect=${intersect:="46.5,8.1"}

# tiles to download and patch, comma-separated
tiles=${tiles:="32TMS"}

# maximum cloud cover fraction
cloudcover=${cloudcover:="100"}

# maximum number of rows in query
maxrows=${maxrows:="10"}

# region name for composite images
region=${region:="aletsch"}

# wsen extent in UTM local zone coordinates, comma-separated
extent=${extent:="410000,5135000,450000,5165000"}

# spatial resolution in meters
resolution=${resolution:="10"}

# maximum percentage of null values
nullvalues=${nullvalues:="50"}

# offline mode
offline=${offline:="no"}


# Download requested tiles
# ------------------------

# change to input base directory
cd $basedir

# if not in offline mode
if [ "$offline" != "yes" ]
then

    # parse intersect if list of four numbers
    if [[ "$intersect" =~ ^[\-0-9.]*,[\-0-9.]*,[\-0-9.]*,[\-0-9.]*$ ]]
    then
        read w s e n <<< $(echo "$intersect" | tr ',' ' ')
        intersect="POLYGON(($w $s,$e $s,$e $n,$w $n,$w $s))"
    fi

    # search for products and save to searchresults.xml
    query="platformname:Sentinel-2 AND "
    query+="footprint:\"intersects(${intersect})\" AND "
    query+="cloudcoverpercentage:[0 TO ${cloudcover}]"
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
        sensdate=$(grep "SENSING_TIME" $datadir/*.xml)
        sensdate=${sensdate#*>}
        sensdate=${sensdate%<*}
        sensdate=$(date -u -d$sensdate +%Y%m%d_%H%M%S_%3N)

        # on error, assume xml file is broken and remove it
        if [ "$?" -ne "0" ]
        then
            echo "Error, removing $datadir/*.xml ..."
            rm $datadir/*.xml
            continue
        fi

        # build RGB VRT
        ofile_rgb="scenes/S2A_${sensdate}_T${tile}_RGB.vrt"
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
        ofile_irg="scenes/S2A_${sensdate}_T${tile}_IRG.vrt"
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
sensdates=$(echo "$scenes" | cut -c 5-23 | uniq)

# loop on sensing dates
for sensdate in $sensdates
do

    # skip date if both files are already here
    ofile_rgb="composite/$region/rgb/S2A_${sensdate}_RGB"
    ofile_irg="composite/$region/irg/S2A_${sensdate}_IRG"
    [ -s $ofile_rgb.jpg ] && [ -s $ofile_irg.jpg ] && continue
    [ -s $ofile_rgb.txt ] && [ -s $ofile_irg.txt ] && continue

    # find how many scenes correspond to requested tiles over region
    scenes_rgb=$(find scenes | egrep "S2A_${sensdate}_T(${tiles//,/|})_RGB.vrt")
    scenes_irg=$(find scenes | egrep "S2A_${sensdate}_T(${tiles//,/|})_IRG.vrt")
    n=$(echo $scenes_rgb | wc -w)

    # assemble mosaic VRT in temporary files
    gdalargs="-q -te ${extent//,/ } -tr $resolution $resolution"
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
        convert -gamma 5.05,5.10,4.85 -sigmoidal-contrast 15,50% \
                -modulate 100,150 $sharpargs -quality 85 -quiet \
                $ofile_rgb.tif $ofile_rgb.jpg
        echo -e "$worldfile" > $ofile_rgb.jpw
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
        convert -gamma 5.50,5.05,5.10 -sigmoidal-contrast 15,50% \
                -modulate 100,150 $sharpargs -quality 85 -quiet \
                $ofile_irg.tif $ofile_irg.jpg
        echo -e "$worldfile" > $ofile_irg.jpw
    fi

done

# remove temporary mosaic VRTs
[ -f tmp_$$_rgb.vrt ] && rm tmp_$$_rgb.vrt
[ -f tmp_$$_irg.vrt ] && rm tmp_$$_irg.vrt

# happy end
exit 0

