#!/usr/bin/env python
# Copyright (c) 2018, Julien Seguinot <seguinot@vaw.baug.ethz.ch>
# GNU General Public License v3.0+ (https://www.gnu.org/licenses/gpl-3.0.txt)

"""Build script for sentinelflow."""

from setuptools import setup

with open('README.rst', 'r') as f:
    README = f.read()

setup(name='sentinelflow',
      version='0.1.3',
      description=('Automated satellite image workflow for Sentinel-2.'),
      long_description=README,
      long_description_content_type='text/x-rst',
      url='http://github.com/juseg/sentinelflow',
      author='Julien Seguinot',
      author_email='seguinot@vaw.baug.ethz.ch',
      license='gpl-3.0',
      py_modules=['sentinelflow'],
      install_requires=[''],
      scripts=['sentinelflow.sh'])
