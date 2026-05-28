services:
  vpot:
    container_name: vpot
    image: vpot:latest
    volumes:
      - ./data:/root/.picoclaw
    network_mode: host
    command: /usr/local/bin/supd -c etc/supd/supd.ini
    logging: # /var/lib/docker/containers/<docker container is>/<id>-json.log
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "10"
    restart: unless-stopped
volumes:
  data:

