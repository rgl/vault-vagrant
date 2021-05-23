#!/bin/bash
set -eux

pushd /vagrant/examples/python/use-postgresql

# install dependencies.
apt-get install -y python3-pip
python3 -m pip install -r requirements.txt

# run.
python3 main.py

popd
