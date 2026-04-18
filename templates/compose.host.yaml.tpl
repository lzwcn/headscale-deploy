# Generated from template
# Official image: __HEADSCALE_IMAGE__
services:
  __HS_CONTAINER__:
    container_name: __HS_CONTAINER__
    image: __HEADSCALE_IMAGE__:__HEADSCALE_TAG__
    restart: unless-stopped
    volumes:
      - __HS_CONF_DIR__:/etc/headscale
      - __HS_DATA_DIR__:/var/lib/headscale
    network_mode: host
    command: serve
    labels:
      org.opencontainers.image.source: "__OFFICIAL_GIT__"
