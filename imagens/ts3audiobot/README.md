# TS3AudioBot for arm64

Setup the data directory
```sh
mkdir -p $(pwd)/ts3bot
chown -R 1001:1001 $(pwd)/ts3bot
```

Run the initial setup to generate all the initial configuration files:
```sh
docker run --name ts3audiobot -it -v $(pwd)/ts3bot:/app/data -p 58913:58913 igorferreir4/ts3audiobot:alpha-net60
```

After configuring the bot, turn it off by pressing CRTL+C. Then run the actual container again as a daemon:
```sh
docker run --name ts3audiobot -d -v $(pwd)/ts3bot:/app/data -p 58913:58913 igorferreir4/ts3audiobot:alpha-net60
```

Or docker-compose.yml:
```sh
  ts3audiobot:
    image: igorferreir4/ts3audiobot:alpha-net60
    container_name: ts3audiobot
    restart: always
    ports:
      - 58913:58913
    volumes:
      - ./ts3bot:/app/data
```