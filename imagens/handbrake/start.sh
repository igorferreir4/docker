#!/bin/bash

trap 'exit 2' TERM INT

shopt -s globstar
shopt -s nullglob
for f in **/*.{avi,AVI,ogm,OGM,wmv,WMV,flv,FLV,mkv,MKV,mov,MOV,m4v,M4V}; do
    printf '\033[1;34;40m'
    echo "Converting $f"
    printf '\033[0m'
    HandBrakeCLI -i "$f" --preset "Very Fast 1080p30" "${f:0:-5}.mp4" && rm "$f"
done
for f in **/*.{divx,DIVX,webm,WEBM}; do
    printf '\033[1;34;40m'
    echo "Converting $f"
    printf '\033[0m'
    HandBrakeCLI -i "$f" --preset "Very Fast 1080p30" "${f:0:-5}.mp4" && rm "$f"
done