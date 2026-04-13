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
__OPTIONAL_PORTS_BLOCK__
    command: serve
    networks:
      - __HS_DOCKER_NETWORK__
    labels:
      org.opencontainers.image.source: "__OFFICIAL_GIT__"

networks:
  __HS_DOCKER_NETWORK__:
    external: true
