services:
  vpot:
    container_name: vpot
    image: docker.lib10.cn/lib10/vpot:v0.0.3
    volumes:
      - ./data:/root/.picoclaw
    ports:
      - 18800:18800
    command: /usr/local/bin/supd -c etc/supd/supd.ini
    logging: # /var/lib/docker/containers/<docker container is>/<id>-json.log
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "10"
    restart: unless-stopped
volumes:
  data:

