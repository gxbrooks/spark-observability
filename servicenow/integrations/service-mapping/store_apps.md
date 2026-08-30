# Service Mapping Store applications

`store_apps.yml` is the desired-state list of ServiceNow Store apps and plugins
for tag-based Service Mapping, in install order. Pins are advisory;
`service-mapping/install.yml` warns on drift but does not auto-upgrade on shared
instances.
