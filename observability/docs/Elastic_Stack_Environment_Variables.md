
# Elastic Stack 
## 1.  Logstash Environment Variables
## 1.1  Java/JVM Variables
Since Logstash runs on Java, it inherits all standard Java environment variables:

| Variable | Description |
|----------|------------|
| JAVA_HOME | Path to Java installation |
| JAVA_OPTS | General JVM options |
| LS_JAVA_OPTS | Logstash-specific JVM options |
| JSVC_OPTS | Java Service Wrapper options (when running as service) |

## 1.1  Path and Home Variables

| Variable | Description |
|----------|------------|
| LS_HOME | Logstash installation directory |
| LS_PATH_SETTINGS | Directory containing logstash.yml and other config files |
| LS_PATH_DATA | Data directory (default: LS_HOME/data) |
| LS_PATH_LOGS | Log directory (default: LS_HOME/logs) |
| LS_PLUGIN_PATH | Additional plugin directories |

## 1.1  Configuration Variables

| Variable | Description |
|----------|------------|
| LS_CONFIG_PATH | Path to logstash.yml (default: LS_PATH_SETTINGS/logstash.yml) |
| PATH_CONF | Directory containing pipelines.yml and pipeline configs |
| LS_PIPELINES_FILE | Path to pipelines.yml file |

## 1.1  Performance and Memory Variables

| Variable | Description |
|----------|------------|
| LS_HEAP_SIZE | Java heap size (e.g., -Xmx4g -Xms4g) |
| LS_OPTS | Additional command-line options |
| LS_OPEN_FILES | Maximum number of open file descriptors |

## 1.  Kibana Environment Variables
## 1.1  Server Configuration

| Variable | Description |
|----------|------------|
| SERVER_HOST | Host address (default: localhost) |
| SERVER_PORT | Port to listen on (default: 5601) |
| SERVER_BASEPATH | Base path if running behind a proxy |
| SERVER_PUBLICBASEURL | Full public URL |
| SERVER_SSL_ENABLED | Enable SSL (default: false) |
| SERVER_SSL_CERTIFICATE | Path to SSL certificate |
| SERVER_SSL_KEY | Path to SSL key |

## 1.1  Elasticsearch Connection

| Variable | Description |
|----------|------------|
| ELASTICSEARCH_HOSTS | Comma-separated list of Elasticsearch nodes |
| ELASTICSEARCH_USERNAME | Username for Elasticsearch |
| ELASTICSEARCH_PASSWORD | Password for Elasticsearch |
| ELASTICSEARCH_APIKEY | API key alternative to username/password |
| ELASTICSEARCH_SSL_VERIFICATIONMODE | Certificate verification (none, certificate, full) |
| ELASTICSEARCH_SSL_CERTIFICATEAUTHORITIES | Path to CA certificate |

## 1.1  Security & Authentication

| Variable | Description |
|----------|------------|
| ELASTICSEARCH_SECURITY_ENABLED | Enable security features |
| XPACK_SECURITY_ENCRYPTIONKEY | Encryption key for saved objects |
| XPACK_SECURITY_SECURECOOKIES_ENABLED | Enable secure cookies |
| XPACK_SECURITY_SAMESITE_COOKIES | SameSite cookie setting |

## 1.1  Feature Toggles

| Variable | Description |
|----------|------------|
| XPACK_ENCRYPTEDSAVEDOBJECTS_ENCRYPTIONKEY | Encryption key for saved objects |
| XPACK_REPORTING_ENCRYPTIONKEY | Encryption key for reporting |
| XPACK_FLEET_AGENTS_ENABLED | Enable Fleet agent management |
| XPACK_APM_ENABLED | Enable APM integration |
| XPACK_MAPS_ENABLED | Enable Maps feature |

## 1.  Elasticsearch Environment Variables
## 1.1  Java/JVM Variables

| Variable | Description |
|----------|------------|
| JAVA_HOME | Path to Java installation directory |
| ES_JAVA_HOME | Elasticsearch-specific Java home path |
| ES_JAVA_OPTS | Additional JVM options for Elasticsearch |
| JAVA_OPTS | General JVM options (used if ES_JAVA_OPTS not set) |

## 1.1  Path and Directory Variables

| Variable | Description |
|----------|------------|
| ES_HOME | Elasticsearch installation directory |
| ES_PATH_CONF | Configuration directory path |
| ES_PATH_DATA | Data directory path(s), comma-separated |
| ES_PATH_LOGS | Logs directory path |
| ES_TMPDIR | Temporary directory path |
| ES_PLUGINS | Plugins directory path |

## 1.1  Cluster and Node Variables

| Variable | Description |
|----------|------------|
| CLUSTER_NAME | Name of the Elasticsearch cluster |
| NODE_NAME | Name of the current node |
| NODE_ROLES | Comma-separated list of node roles |
| DISCOVERY_TYPE | Discovery mechanism type |

## 1.1  Network and Discovery Variables

| Variable | Description |
|----------|------------|
| NETWORK_HOST | Network host binding address |
| HTTP_HOST | HTTP interface host address |
| HTTP_PORT | HTTP interface port |
| TRANSPORT_HOST | Transport interface host address |
| TRANSPORT_PORT | Transport interface port |
| DISCOVERY_SEED_HOSTS | Comma-separated list of seed nodes for discovery |
| INITIAL_MASTER_NODES | Comma-separated list of initial master-eligible nodes |

## 1.1  Security Variables

| Variable | Description |
|----------|------------|
| ELASTIC_PASSWORD | Password for built-in elastic user |
| xpack.security.enabled | Enable security features |
| xpack.security.http.ssl.enabled | Enable SSL for HTTP interface |
| xpack.security.transport.ssl.enabled | Enable SSL for transport interface |
| xpack.security.authc anonymous.username | Anonymous access username |
| xpack.security.authc anonymous.roles | Anonymous access roles |

## 1.1  SSL/TLS Certificate Variables

| Variable | Description |
|----------|------------|
| xpack.security.http.ssl.keystore.path | HTTP SSL keystore path |
| xpack.security.http.ssl.truststore.path | HTTP SSL truststore path |
| xpack.security.transport.ssl.keystore.path | Transport SSL keystore path |
| xpack.security.transport.ssl.truststore.path | Transport SSL truststore path |
| CERTS_DIR | Directory containing SSL certificates |

## 1.1  Memory and Performance Variables

| Variable | Description |
|----------|------------|
| ES_HEAP_SIZE | Java heap size allocation |
| ES_JAVA_OPTS | Additional JVM options |
| MAX_LOCKED_MEMORY | Maximum locked memory limit |
| MAX_MAP_COUNT | Maximum memory map count (Linux) |

## 1.1  Bootstrap and System Variables

| Variable | Description |
|----------|------------|
| ES_STARTUP_SLEEP_TIME | Sleep time before startup (seconds) |
| ES_SKIP_SET_KERNEL_PARAMETERS | Skip kernel parameter configuration |
| ES_DISTRIBUTION_FLAVOR | Distribution flavor (default, oss) |
| ES_DISTRIBUTION_TYPE | Distribution type (tar, docker, rpm, deb) |

## 1.1  Docker-Specific Variables

| Variable | Description |
|----------|------------|
| TAKE_FILE_OWNERSHIP | Change file ownership in Docker containers |
| ELASTICSEARCH_PLUGINS | Comma-separated list of plugins to install |
| ELASTICSEARCH_OPTS | Additional command line options |

## 1.1  License and Feature Variables

| Variable | Description |
|----------|------------|
| xpack.license.self_generated.type | License type (basic, trial) |
| xpack.monitoring.collection.enabled | Enable monitoring collection |
| xpack.ml.enabled | Enable machine learning features |

These environment variables can be used to configure Elasticsearch without modifying configuration files directly, and they typically override settings in elasticsearch.yml when set.
