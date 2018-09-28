.. Copyright (c) 2017--2018, Julien Seguinot <seguinot@vaw.baug.ethz.ch>
.. GNU General Public License v3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)

Sentinelflow
============

Search, download and patch Copernicus_ Sentinel-2_ data into appealing color
images. Colors are adapted to human perception and fit for dark oceans as well
as bright snow surfaces.

Requires GDAL_, ImageMagick_, XMLStarlet_, and a registration_ to the
Copernicus Open Access Hub. A Python port is under preparation.

Installation::

   pip install sentinelflow

To fetch the latest cloud-free image over the Aletsch Glacier use::

   sentinelflow.sh --user USERNAME --pass PASSWORD --cloudcover 10 \
                   --intersect 46.4,8.1 --maxrows 1 --tiles 32TMS \
                   --extent 417000,5138000,432000,5158000


Please refer to the Sentinel-2 `data products`_ documentation to find your
corresponding tile(s). The image extent is given in UTM_ coordinates of the
local zone. For additional command-line help use::

   sentinelflow.sh --help

Please acknowledge usage in all derivative products, for instance with the
mention:

   Contains modified Copernicus Sentinel data (year).
   Processed with Sentinelflow (version).


.. Documentation links

.. _Copernicus: http://copernicus.eu
.. _data products: https://sentinel.esa.int/web/sentinel/missions/sentinel-2/data-products
.. _registration: https://scihub.copernicus.eu/dhus/#/self-registration
.. _Sentinel-2: https://sentinels.copernicus.eu/web/sentinel/missions/sentinel-2
.. _UTM: https://en.wikipedia.org/wiki/Universal_Transverse_Mercator_coordinate_system

.. Software links

.. _GDAL: https://www.gdal.org
.. _ImageMagick: https://www.imagemagick.org
.. _XMLStarlet: http://xmlstar.sourceforge.net
