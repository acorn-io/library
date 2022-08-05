#!/bin/bash

committed_tag=${GITHUB_REF#refs/*/}

IFS='-' read -r image tag <<< "$committed_tag"

echo "IMAGE=${image}" >> $GITHUB_ENV
echo "TAG=${tag}" >> $GITHUB_ENV
