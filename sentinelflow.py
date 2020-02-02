#!/usr/bin/env python
# Copyright (c) 2016--2020, Julien Seguinot <seguinot@vaw.baug.ethz.ch>
# GNU General Public License v3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)

"""
Automated satellite image workflow for Sentinel-2.
"""

import argparse


def main():
    """Main program for command-line execution."""

    # custom help formatter
    class _CompactHelpFormatter(argparse.RawTextHelpFormatter,
                                argparse.ArgumentDefaultsHelpFormatter):
        """Help formatter without metavar display."""
        def _format_action_invocation(self, action):
            return ', '.join(action.option_strings)

    # argument parser
    parser = argparse.ArgumentParser(
        add_help=False,
        description=__doc__,
        epilog='''
Sentinelflow (c) 2016-2020 Julien Seguinot <seguinot@vaw.baug.ethz.ch>.
Please report bugs at: https://github.com/juseg/sentinelflow.
Cite code archives at: https://doi.org/10.5281/zenodo.1439483.
        ''',
        formatter_class=_CompactHelpFormatter,
        usage='sentinelflow.sh --user USER --pass PASS [options]',
        )

    # general options
    group = parser.add_argument_group('General options')
    group.add_argument('-h', '--help', action='help',
                       help='display this help message and exit')
    group.add_argument('-u', '--user',
                       help='username at Copernicus Open Access Hub')
    group.add_argument('-p', '--pass',
                       help='password at Copernicus Open Access Hub')
    group.add_argument('-w', '--workdir', default='.', metavar='',
                       help='working directory')

    # query and download options
    group = parser.add_argument_group('Query and download')
    group.add_argument('-c', '--cloudcover',
                       help='maximum cloud cover fraction')
    group.add_argument('-d', '--daterange',
                       help='range of sensing date in query')
    group.add_argument('-i', '--intersect',
                       help='point LAT,LON or rectangle W,E,S,N')
    group.add_argument('-m', '--maxrows', default=10,
                       help='maximum number of rows in query')
    group.add_argument('-t', '--tiles', default='',
                       help='tiles to download, comma-separated')

    # image composition options
    group = parser.add_argument_group('Image composition')
    group.add_argument('-b', '--bands', default='RGB', metavar='',
                       help='color bands (IRG, RGB) for composition')
    group.add_argument('-e', '--extent', metavar='',
                       help='W,S,E,N extent in local UTM coordinates')
    group.add_argument('-n', '--name', metavar='',
                       help='region name for composite images')
    group.add_argument('-r', '--resolution', default='10', metavar='',
                       help='spatial resolution in meters')
    group.add_argument('-s', '--sigma', default='15,50%', metavar='',
                       help='sigmoidal contrast parameters')
    group.add_argument('-x', '--nullvalues', default=50, metavar='',
                       help='maximum percentage of null values')

    # flags
    group = parser.add_argument_group('Flags')
    group.add_argument('-1', '--sentinel1', action='store_true',
                       help='download sentinel-1 data (experimental)')
    group.add_argument('-f', '--fetchonly', action='store_true',
                       help='download data only, do not patch images')
    group.add_argument('-k', '--keeptiff', action='store_true',
                       help='keep intermediate TIFF images')
    group.add_argument('-o', '--offline', action='store_true',
                       help='offline mode, use local data only')
    args = parser.parse_args()


if __name__ == '__main__':
    main()
