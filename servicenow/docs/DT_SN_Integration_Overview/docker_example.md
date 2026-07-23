```yaml
services:
  elasticsearch:
    image: elasticsearch:8.15.0
    labels:
      com.docker.compose.project: observability
      com.docker.compose.service: elasticsearch
      servicenow.io/application-service-identifier: elasticsearch
      servicenow.io/environment: on-prem
      servicenow.io/location: my-region
```
