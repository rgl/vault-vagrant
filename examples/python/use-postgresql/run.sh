#!/bin/bash
set -eux

pushd /vagrant/examples/python/use-postgresql

# install dependencies.
apt-get install -y python3-pip
python3 -m pip install -r requirements.txt

# run.
# NB this will make vault create a new postgresql user.
python3 main.py

# show the current postgresql users and comments.
# NB the new vault created postgresql user should appear in this listing;
#    the postgresql user should be valid for an hour.
sudo -sHu postgres psql -c '\du+'

popd
