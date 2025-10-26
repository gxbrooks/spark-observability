# Grafana Plugin Development Guide

This document covers the complete process of building, deploying, and installing Grafana plugins, specifically focusing on the volkovlabs-text-panel plugin.

## Table of Contents

1. [Directory Structure](#directory-structure)
2. [Build Process](#build-process)
3. [Deployment Process](#deployment-process)
4. [Installation in Grafana](#installation-in-grafana)
5. [Troubleshooting](#troubleshooting)
6. [Plugin Architecture](#plugin-architecture)

## Directory Structure

### Source Repository Structure

```
business-text/                    # GitHub repository
├── src/                          # Source code
│   ├── module.ts                 # Main entry point
│   ├── components/               # React components
│   │   └── TextPanel.tsx         # Main panel component
│   └── types.ts                  # TypeScript types
├── dist/                         # Build output (generated)
│   ├── module.js                 # Webpack bundle
│   ├── module.js.map             # Source maps
│   └── plugin.json               # Plugin metadata copy
├── plugin.json                   # Plugin metadata source
├── package.json                  # NPM dependencies
├── tsconfig.json                 # TypeScript config
├── webpack.config.js             # Webpack config
└── README.md                     # Documentation
```

### Deployment Structure

```
elastic-on-spark/
└── observability/
    └── grafana/
        ├── plugins/
        │   └── volkovlabs-text-panel/    # Deployed plugin
        │       ├── module.js             # From dist/
        │       ├── module.js.map         # From dist/
        │       ├── plugin.json           # From dist/
        │       ├── LICENSE               # From root
        │       └── README.md             # From root
        └── docs/
            └── Plugins.md                # This document
```

### Docker Mount Structure

```
docker-compose.yml maps:
  ./grafana/plugins -> /var/lib/grafana/plugins

Results in Grafana container:
/var/lib/grafana/plugins/
└── volkovlabs-text-panel/
    ├── module.js
    ├── module.js.map
    └── plugin.json
```

## Build Process

### Prerequisites

1. **Node.js v20 or higher**
2. **Yarn package manager**
3. **Git**

Install on devops client:
```bash
./linux/assert_grafana_build_utilities.sh
```

### Manual Build Steps

1. **Clone the repository:**
```bash
cd /tmp
git clone https://github.com/VolkovLabs/business-text.git
cd business-text
```

2. **Install dependencies:**
```bash
yarn install
```

3. **Build the plugin:**
```bash
yarn build
```

4. **Verify build output:**
```bash
ls -la dist/
# Should contain: module.js, module.js.map, plugin.json
```

### Automated Build

Use the Ansible playbook:
```bash
ansible-playbook ansible/playbooks/observability/build.yml
```

This will:
- Clone the business-text repository to `/tmp/grafana-plugin-build/`
- Install all dependencies
- Run the webpack build
- Copy `dist/` contents to `observability/grafana/plugins/volkovlabs-text-panel/`

### Build Output Verification

After building, verify the plugin structure:

```bash
ls -la observability/grafana/plugins/volkovlabs-text-panel/
# Should show:
# - module.js (100KB+ webpack bundle)
# - module.js.map (source maps)
# - plugin.json (metadata)
# - LICENSE, README.md
```

## Deployment Process

### Manual Deployment

1. **Build the plugin** (see Build Process above)

2. **Copy dist/ directory:**
```bash
cp -r /tmp/grafana-plugin-build/business-text/dist/* \
  ~/repos/elastic-on-spark/observability/grafana/plugins/volkovlabs-text-panel/
```

### Automated Deployment

Use the Ansible playbook:
```bash
ansible-playbook ansible/playbooks/observability/deploy.yml -i ansible/inventory.yml --limit GaryPC-WSL
```

This deploys the plugin to the target host at:
`/home/ansible/observability/grafana/plugins/volkovlabs-text-panel/`

### Deployment Verification

Check that the plugin files are properly deployed:

```bash
# On target host
ls -la /home/ansible/observability/grafana/plugins/volkovlabs-text-panel/
# Should show all required files with correct permissions
```

## Installation in Grafana

### Docker Compose Configuration

The plugin is mounted into Grafana via docker-compose.yml:

```yaml
grafana:
  image: grafana/grafana-enterprise:11.3.0
  volumes:
    - "./grafana/plugins:/var/lib/grafana/plugins"
  environment:
    - GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=volkovlabs-text-panel
```

### Plugin Loading Process

1. **Grafana scans** `/var/lib/grafana/plugins/` on startup
2. **For each subdirectory**, it looks for:
   - `plugin.json` - Plugin metadata
   - `module.js` - Webpack-bundled plugin code
3. **The plugin is registered** if:
   - Both files exist
   - `module.js` exports `plugin` or `PanelCtrl`
   - Plugin is allowed (signed or in allow list)

### Verification

After starting Grafana:
```bash
# Check Grafana logs
docker logs grafana 2>&1 | grep volkovlabs

# Should see:
# logger=plugins.registration msg="Plugin registered" pluginId=volkovlabs-text-panel
```

Access Grafana UI and verify plugin appears in panel type selector.

## Troubleshooting

### "Error loading: volkovlabs-text-panel"

**Cause**: Missing dist/ directory or incorrect file structure

**Solution**: Ensure you deployed the `dist/` directory contents, not source files

### "missing export: plugin or PanelCtrl"

**Cause**: module.js is not webpack-bundled or has wrong export format

**Solution**: Rebuild the plugin using `yarn build`, do not copy source files

### "Plugin is unsigned"

**Cause**: Plugin not in allowed unsigned plugins list

**Solution**: Add to grafana.ini:
```ini
[plugins]
allow_loading_unsigned_plugins = volkovlabs-text-panel
```

### Build fails with "The engine 'node' is incompatible"

**Cause**: Node.js version too old

**Solution**: Install Node.js v20:
```bash
nvm install 20
nvm use 20
```

### Build fails with "Cannot find module"

**Cause**: Dependencies not installed

**Solution**: Run `yarn install` in the plugin directory

### Plugin loads but dashboard shows errors

**Cause**: Dashboard using wrong panel type

**Solution**: Update dashboard JSON to use `type: "volkovlabs-text-panel"`

## Plugin Architecture

### Key Components

1. **module.ts** - Main entry point that exports the plugin
2. **TextPanel.tsx** - React component for the panel UI
3. **types.ts** - TypeScript type definitions
4. **plugin.json** - Plugin metadata and configuration

### Export Requirements

Grafana expects the compiled `module.js` to export:

```typescript
export const plugin = new PanelPlugin<TextPanelOptions>(TextPanel)
  .setPanelOptions((builder) => {
    return builder
      .addTextInput({
        path: 'content',
        name: 'Content',
        description: 'Text content to display',
        defaultValue: 'Hello World!',
      });
  });
```

### Build Tools

- **TypeScript**: Compiles `.ts` files to `.js`
- **Webpack**: Bundles all dependencies into single module
- **Yarn**: Package manager for dependencies
- **@grafana/toolkit**: Grafana-specific build tools

### File Size Expectations

- **module.js**: 100KB+ (webpack bundle with React, dependencies)
- **module.js.map**: 200KB+ (source maps for debugging)
- **plugin.json**: <1KB (metadata only)

## Best Practices

1. **Always build from source** - Don't copy raw JavaScript files
2. **Use the dist/ directory** - Grafana expects webpack bundles
3. **Verify build output** - Check file sizes and exports
4. **Test in development** - Use Docker for consistent environment
5. **Document changes** - Update this guide when modifying build process

## Related Files

- `ansible/playbooks/observability/build.yml` - Build automation
- `ansible/playbooks/observability/deploy.yml` - Deployment automation
- `observability/docker-compose.yml` - Docker configuration
- `observability/grafana/grafana.ini` - Grafana configuration
- `linux/assert_grafana_build_utilities.sh` - Build prerequisites
