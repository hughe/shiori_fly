#!/bin/bash

if [ ! -f ./fly.toml ]; then
    echo "No fly.toml file found"
    exit 1
fi

fly deploy
res=$?

if [ $res -eq 0 ]; then
    echo "Deployed"
else 
    echo "fly deploy failed: $res"
    exit 2
fi

# fly scale count 1
# $res=$?

# if [ $res -eq 0 ]; then
#     echo "Scaled"
# else
#     echo "fly scale failed: $res"
#     exit 2
# fi

exit 0
