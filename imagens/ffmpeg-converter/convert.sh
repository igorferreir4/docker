#!/bin/bash

trap 'exit 2' TERM INT

shopt -s globstar
shopt -s nullglob
for f in **/*.{avi,ogm,wmv,AVI,OGM,WMV,flv,FLV,mkv,MKV,mov,MOV,m4v,M4V}; do
    printf '\033[1;34;40m'
    echo "Converting $f"
    printf '\033[0m'
    ffmpeg -i "$f" -c:v libx264 "${f:0:-4}.mp4" -preset ultrafast && rm "$f"
done
for f in **/*.{divx,DIVX,webm,WEBM}; do
    printf '\033[1;34;40m'
    echo "Converting $f"
    printf '\033[0m'
    ffmpeg -i "$f" -c:v libx264 "${f:0:-5}.mp4" -preset ultrafast && rm "$f"
done