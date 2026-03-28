# DNS and IP Address Management Architecture

**Version**: 1.1  
**Date**: March 28, 2026  
**Status**: Active

## Problem Statement

Dynamic IP addresses from DHCP cause cascading failures when hosts change IPs:
- Observability agents can't reach Elasticsearch
- Certificate verification fails (hostname mismatch)
- Services become unreachable
- /etc/hosts entries become stale

## Design Principle

**Use DNS names exclusively in all configurations.** Never hardcode IP addresses in:
- Application configurations
- Ansible variables
- Docker Compose files
- Environment variables
- Certificate SANs

## Recommended Solutions (Best to Good)

### 1. DHCP Reservations (Best Practice)

**What**: Configure router/DHCP server to always assign same IP to each MAC address

**Advantages**:
- ✅ Centralized management
- ✅ Survives host reboots
- ✅ No manual configuration on hosts
- ✅ Works with DNS or /etc/hosts
- ✅ Industry standard approach

**Disadvantages**:
- ⚠️ Requires router access
- ⚠️ Router-specific configuration

**Implementation**:
```
Router DHCP Settings:
  MAC: C8:FF:BF:01:1A:A4 → IP: 192.168.1.76  (Lab1)
  MAC: <Lab2-MAC>       → IP: 192.168.1.48  (Lab2)
  MAC: <Lab3-MAC>       → IP: 192.168.1.49  (Lab3, observability / Docker)
```

**How to Find MAC Addresses**:
```bash
# On each host
ip addr show | grep -A 1 "state UP" | grep "link/ether"
```

### 2. Static IP Configuration (Reliable)

**What**: Configure static IP addresses on each host's network interface

**Advantages**:
- ✅ Complete control
- ✅ No dependency on DHCP
- ✅ Guaranteed consistency
- ✅ Documented in infrastructure-as-code

**Disadvantages**:
- ⚠️ Manual configuration on each host
- ⚠️ Must avoid conflicts with DHCP range
- ⚠️ Requires network planning

**Implementation**: Via Ansible playbook that configures netplan/NetworkManager

### 3. Local DNS Server (Enterprise Solution)

**What**: Run bind9, dnsmasq, or Pi-hole for local DNS resolution

**Advantages**:
- ✅ Professional solution
- ✅ Supports dynamic updates
- ✅ Can integrate with DHCP
- ✅ Provides DNS caching
- ✅ Can block ads/malware (Pi-hole)

**Disadvantages**:
- ⚠️ Additional service to maintain
- ⚠️ Single point of failure (needs HA)
- ⚠️ More complex setup

**Recommended**: If you have a spare Raspberry Pi or VM

### 4. Manual /etc/hosts Management (Practical Fallback)

**What**: Manually maintain /etc/hosts on each host when IP changes occur

**Advantages**:
- ✅ No external dependencies
- ✅ Works offline
- ✅ Simple to understand and implement
- ✅ Direct control

**Disadvantages**:
- ⚠️ Manual work required after each IP change
- ⚠️ Must be done on each host individually
- ⚠️ Easy to forget or miss a host

**Note**: Cannot be automated via Ansible due to circular dependency (Ansible requires network to be functional)

### 5. mDNS/Avahi (Limited Use Case)

**What**: Use `.local` domain with multicast DNS

**Advantages**:
- ✅ Zero configuration
- ✅ Works out of box on Linux/macOS

**Disadvantages**:
- ❌ Doesn't work well in Docker containers
- ❌ Windows support requires Bonjour
- ❌ Not routable across subnets
- ❌ Can't use custom TLDs like `.lan` (router compatibility issues)

**Verdict**: Not suitable for this environment

## Recommended Architecture

### Primary Solution: DHCP Reservations + Automated /etc/hosts

**Rationale**: 
- DHCP reservations prevent most IP changes
- Automated /etc/hosts provides fallback and visibility
- Validation playbooks detect mismatches early

**Flow**:
```
1. Router DHCP assigns consistent IPs based on MAC address
2. Ansible playbook validates DNS resolution
3. If mismatch detected, updates /etc/hosts and alerts
4. Services use DNS names exclusively (never IPs)
```

## Implementation

### Manual Procedures (No Ansible Automation)

Since Ansible depends on a functional network, network management cannot be automated via Ansible (circular dependency).

**When IP Addresses Change:**

1. **Detect the change**:
   ```bash
   # On each host, check current IP
   hostname -I
   
   # Check DNS resolution
   getent hosts Lab3.lan
   getent hosts Lab1.lan
   getent hosts Lab2.lan
   ```

2. **Update /etc/hosts manually** on each affected host:
   ```bash
   # Edit /etc/hosts
   sudo nano /etc/hosts
   
   # Add/update entries:
   192.168.1.49   Lab3.lan Lab3      # Observability stack (Docker Engine)
   192.168.1.76   Lab1.lan Lab1      # Kubernetes worker
   192.168.1.48   Lab2.lan Lab2      # Kubernetes master, NFS, Hadoop (see inventory)
   ```

3. **Test connectivity**:
   ```bash
   ping -c 3 Lab3.lan
   ping -c 3 Lab1.lan
   ping -c 3 Lab2.lan
   ```

4. **Restart affected services**:
   ```bash
   # If Elastic Agent is affected
   sudo systemctl restart elastic-agent
   
   # If observability services affected, restart from correct host
   cd ~/repos/spark-observability/ansible
   ansible-playbook -i inventory.yml playbooks/observability/stop.yml --limit observability
   ansible-playbook -i inventory.yml playbooks/observability/start.yml --limit observability
   ```

### Documentation Reference

**Host Inventory** (`ansible/inventory.yml`):
- All hosts defined by DNS name (`.lan` suffix)
- Never use IP addresses directly
- Expected IPs documented in comments for reference only

## Certificate Subject Alternative Names (SANs)

Ensure `observability/certs/instances.yml` includes all possible hostnames:

```yaml
instances:
  - name: "es01"
    dns:
      - "es01"
      - "localhost"
      - "Lab3.lan"
      - "Lab3"
    ip:
      - "127.0.0.1"
      - "192.168.1.49"  # Lab3 reservation; DNS names are primary in configs
```

**Principle**: Include DNS names AND current IP for maximum compatibility, but always reference by DNS name in configs.

## Validation Strategy

### Pre-Flight Checks

All playbooks should validate DNS before proceeding:

```yaml
- name: Validate Lab3.lan resolves correctly (observability host)
  shell: |
    RESOLVED_IP=$(getent hosts Lab3.lan | awk '{print $1}')
    EXPECTED_IP="{{ hostvars['Lab3']['ansible_host'] | default('Lab3.lan') }}"
    # Compare to expected_ips in inventory when using fixed reservations
    if [ -z "$RESOLVED_IP" ]; then
      echo "ERROR: Lab3.lan did not resolve"
      exit 1
    fi
  changed_when: false
```

### Health Monitoring

Add to `diagnose.yml` playbooks:
- DNS resolution test for all critical hosts
- Ping test to verify network connectivity
- Certificate SAN validation

## Migration Strategy

### Immediate Actions

1. **Document Current MAC Addresses**:
   ```bash
   ansible all -i ansible/inventory.yml -m shell \
     -a "ip addr show | grep -B 1 '192.168.1' | grep 'link/ether' | awk '{print \$2}'"
   ```

2. **Configure DHCP Reservations** on your router

3. **Reboot all hosts** to verify IPs are stable

4. **Run validation playbook** to confirm DNS resolution

### Long-Term Best Practices

1. **Never use IP addresses** in configurations (only DNS names)
2. **Run network diagnostics** before deploying new services
3. **Monitor IP changes** via automated checks
4. **Document network topology** in version control
5. **Include IPs in certificate SANs** as backup (but use DNS names)

## Troubleshooting

### Issue: Host IP Changed

**Detection**:
```bash
ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/network/diagnose.yml
```

**Resolution**:
```bash
# Update /etc/hosts on all hosts
ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/network/manage_hosts.yml

# Restart services to reconnect
ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/elastic-agent/stop.yml
ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/elastic-agent/start.yml
```

### Issue: Certificate hostname mismatch

**Symptoms**: `x509: certificate is valid for X, not Y`

**Resolution**: Regenerate certificates with updated SANs
```bash
# Update observability/certs/instances.yml
# Then force regenerate
FORCE_REGEN=1 ansible-playbook -i inventory.yml \
  playbooks/observability/start.yml --limit observability
```

## Monitoring and Detection

### Manual Monitoring Procedures

Since network issues prevent Ansible from running, monitoring must be done manually or via local scripts:

1. **Daily IP Check** (on each host):
   ```bash
   # Check if current IP matches /etc/hosts
   hostname -I
   getent hosts $(hostname).local
   ```

2. **Service Health Indicators**:
   - Elastic Agent logs show connection timeouts
   - Grafana dashboards show no data
   - `docker ps` shows no observability containers (if on wrong host)

3. **Quick Network Test**:
   ```bash
   ping -c 1 Lab3.lan && echo "✅ Lab3 reachable" || echo "❌ Lab3 UNREACHABLE"
   ```

## References

- DHCP Reservations: Best practice for home/small office networks
- Linux Network Configuration: netplan, NetworkManager, systemd-networkd
- DNS Best Practices: RFC 1912, RFC 2606
- Elasticsearch Security: hostname validation, certificate SANs

## Change Log

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-10-22 | Initial architecture document |
| 1.1 | 2026-03-28 | Observability on Lab3.lan; paths and examples for spark-observability/ansible |

