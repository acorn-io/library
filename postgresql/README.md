# PostgreSQL

This Acorn provides a single node PostgreSQL 14.5 (based on Debian Bullseye) instance.

## Pre-req

- storage class for PVs

## Installation

### Revealing generated password

The secret with admin credentials contains the admin user name and password. Password is generated automatically and could be revealed in the following way:

        $ acorn secret expose appname.root-credentials

Where the _appname_ should be substituted with your application name. It will return something like:

        NAME                     TYPE      KEY        VALUE
        root-credentials-ccrh4   basic     password   5h9bq4cl2gw5h5d2
        root-credentials-ccrh4   basic     username   admin


