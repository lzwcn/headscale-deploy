# Generated from template
# Docs: __OFFICIAL_GIT__
server_url: __SERVER_URL__
listen_addr: __LISTEN_ADDR_WITH_PORT__
metrics_listen_addr: 127.0.0.1:9090
grpc_listen_addr: 127.0.0.1:50443
grpc_allow_insecure: false

noise:
  private_key_path: /var/lib/headscale/noise_private.key

prefixes:
  v4: 100.64.0.0/10
  v6: fd7a:115c:a1e0::/48
  allocation: sequential

derp:
  server:
    enabled: __DERP_ENABLED__
    region_id: __DERP_REGION_ID__
    region_code: "__DERP_REGION_CODE__"
    region_name: "__DERP_REGION_NAME__"
    verify_clients: __DERP_VERIFY_CLIENTS__
    stun_listen_addr: "__DERP_STUN_LISTEN_ADDR__"
    private_key_path: /var/lib/headscale/derp_server_private.key
    automatically_add_embedded_derp_region: __DERP_AUTO_ADD_EMBEDDED_REGION__
    ipv4: __DERP_IPV4__
    ipv6: __DERP_IPV6__
  urls:
    __DERP_URLS_BLOCK__
  paths: []
  auto_update_enabled: true
  update_frequency: 3h

disable_check_updates: false
ephemeral_node_inactivity_timeout: 30m

database:
  type: sqlite
  debug: false
  gorm:
    prepare_stmt: true
    parameterized_queries: true
    skip_err_record_not_found: true
    slow_threshold: 1000
  sqlite:
    path: /var/lib/headscale/db.sqlite
    write_ahead_log: true
    wal_autocheckpoint: 1000

log:
  level: info
  format: text

policy:
  mode: file
  path: ""

dns:
  magic_dns: true
  base_domain: __BASE_DOMAIN__
  override_local_dns: true
  nameservers:
    global:
__DNS_GLOBAL_NAMESERVERS_BLOCK__

unix_socket: /var/lib/headscale/headscale.sock
unix_socket_permission: "0770"

logtail:
  enabled: false
randomize_client_port: false

taildrop:
  enabled: true
