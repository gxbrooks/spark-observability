# Elasticsearch — CSDM hierarchy + Docker Compose labels

Combined example for slide panels. Values match `servicenow/regions/brooks-lab/observability-platform.csdm.yaml` and `observability/docker-compose.yml` (service `es01`).

```yaml
# --- CSDM: observability-platform.csdm.yaml ---

business_applications:
  - name: Observability Platform
    identifier: observability-platform
    short_description: Monitoring, logging, metrics, and tracing

business_services:
  - name: Elasticsearch
    identifier: elasticsearch
    short_description: Primary metrics, logs, and trace storage (Elastic Stack)
    parent_business_application: Observability Platform

application_services:
  - name: Elasticsearch
    identifier: elasticsearch
    short_description: Elasticsearch — HTTPS API
    parent_business_service: Elasticsearch
    platform: docker
    service_mapping: tags
    environment: on-prem
    location: brooks-lab
    service_tier: data

# --- Docker Compose: observability/docker-compose.yml (es01) ---

services:
  es01:
    image: elasticsearch-python
    labels:
      com.docker.compose.project: observability
      com.docker.compose.service: es01
      servicenow.io/application-service-identifier: elasticsearch
      servicenow.io/environment: on-prem
      servicenow.io/location: brooks-lab
      servicenow.io/service-tier: data
```

**Join key:** Application Service `identifier` = `servicenow.io/application-service-identifier` on the running container.
