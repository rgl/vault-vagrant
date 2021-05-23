#!/bin/bash
set -eux

pushd /vagrant/examples/python/use-postgresql

# install dependencies.
apt-get install -y python3-pip
python3 -m pip install -r requirements.txt

# run.
python3 main.py

# show the current postgresql users and comments.
sudo -sHu postgres psql -c '\du+'

popd
