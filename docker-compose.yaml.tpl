services:
  vpot:
    container_name: vpot
    image: docker.lib10.cn/vpot/vpot:v0.0.1
    volumes:
      - ./data:/root/.picoclaw
    network_mode: host
    command: ./supd -c /vpot/etc/supd/supd.conf
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "10"
    restart: unless-stopped
volumes:
  data:

