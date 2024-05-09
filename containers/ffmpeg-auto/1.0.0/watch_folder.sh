#!/bin/sh

# Função para converter arquivos MKV para MP4
convert_files() {
    for file in "$1"/*.mkv; do
        ffmpeg -fflags +genpts -i "$file" -y -map 0 -c:V copy -c:a aac -ac 2 -c:s mov_text "${file%.*}.mp4"
        rm "$file"
    done
}

# Função para mover pastas
move_folders() {
    for dir in "$1"/*; do
        if [ -d "$dir" ]; then
            if [ "$(basename "$dir")" != "series" ] && [ "$(basename "$dir")" != "filmes" ]; then
                mv "$dir" /saida/$(basename "$1")/
            fi
        fi
    done
}

# Loop infinito para monitorar a pasta de entrada
while true; do
    inotifywait -r -e create --format '%w%f' /entrada/series /entrada/filmes | while read file; do
        if [ "${file##*.}" = "mkv" ]; then
            sleep 15
            convert_files "$(dirname "$file")"
            move_folders "$(dirname "$file")"
        fi
    done
done