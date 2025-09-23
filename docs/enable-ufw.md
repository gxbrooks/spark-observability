# Enabling UFW with Kubernetes

This document describes how to properly configure UFW (Uncomplicated Firewall) to work with Kubernetes while maintaining pod-to-Service connectivity.

## Prerequisites

- Kubernetes cluster is running and healthy
- Pod-to-Service connectivity is working (tested with `kubectl -n spark exec pod/test-dns -- sh -c 'nc -vz 10.96.0.1 443'`)
- CoreDNS is ready and functioning

## UFW Configuration for Kubernetes

### 1. Configure UFW Defaults

```yaml
- name: Configure UFW for Kubernetes
  blockinfile:
    path: /etc/default/ufw
    block: |
      DEFAULT_FORWARD_POLICY="ACCEPT"
    marker: "# {mark} KUBERNETES FORWARD POLICY"
    create: yes
```

### 2. Add Kubernetes NAT Rules

```yaml
- name: Add Kubernetes NAT rules to UFW
  blockinfile:
    path: /etc/ufw/before.rules
    block: |
      *nat
      :POSTROUTING ACCEPT [0:0]
      -A POSTROUTING -s 10.244.0.0/16 -o {{ ansible_default_ipv4.interface }} -j MASQUERADE
      COMMIT
    marker: "# {mark} KUBERNETES NAT"
    insertafter: "*filter"
    create: yes
```

### 3. Enable IP Forwarding in UFW

```yaml
- name: Enable IP forwarding in UFW
  blockinfile:
    path: /etc/ufw/sysctl.conf
    block: |
      net/ipv4/ip_forward=1
    marker: "# {mark} KUBERNETES IP FORWARD"
    create: yes
```

### 4. Configure UFW Rules

```yaml
- name: Configure UFW rules for Kubernetes
  ufw:
    rule: allow
    port: "{{ item }}"
    proto: tcp
  loop:
    - "6443"  # Kubernetes API server
    - "2379"  # etcd
    - "2380"  # etcd peer
    - "10250" # kubelet
    - "10251" # kube-scheduler
    - "10252" # kube-controller-manager
    - "10255" # kubelet read-only
    - "30000:32767" # NodePort range

- name: Allow SSH
  ufw:
    rule: allow
    port: "22"
    proto: tcp

- name: Allow HTTP/HTTPS for NodePort services
  ufw:
    rule: allow
    port: "{{ item }}"
    proto: tcp
  loop:
    - "80"
    - "443"
```

## Testing Sequence

### Before Enabling UFW

```yaml
- name: Pre-UFW connectivity test
  shell: kubectl -n spark exec pod/test-dns -- sh -c 'nc -vz 10.96.0.1 443 >/dev/null 2>&1 && echo ok || echo fail'
  register: pre_ufw_test
  when: ufw_enabled | default(false)
```

### Enable UFW

```yaml
- name: Enable UFW if requested
  ufw:
    state: enabled
    policy: allow
  when: ufw_enabled | default(false)
```

### After Enabling UFW

```yaml
- name: Post-UFW connectivity test
  shell: kubectl -n spark exec pod/test-dns -- sh -c 'nc -vz 10.96.0.1 443 >/dev/null 2>&1 && echo ok || echo fail'
  register: post_ufw_test
  when: ufw_enabled | default(false)

- name: Fail if connectivity broken after UFW
  fail:
    msg: "Pod connectivity broken after UFW enable. Check UFW rules."
  when: ufw_enabled | default(false) and post_ufw_test.stdout != "ok"
```

## Complete UFW Playbook

```yaml
---
# enable_ufw.yml - Enable UFW with Kubernetes support
- name: Enable UFW for Kubernetes
  hosts: spark_kubernetes:&linux
  become: true
  vars:
    ufw_enabled: true  # Set to true to enable UFW
  tasks:
    - name: Pre-UFW connectivity test
      shell: kubectl -n spark exec pod/test-dns -- sh -c 'nc -vz 10.96.0.1 443 >/dev/null 2>&1 && echo ok || echo fail'
      register: pre_ufw_test
      when: ufw_enabled
      
    - name: Configure UFW for Kubernetes
      blockinfile:
        path: /etc/default/ufw
        block: |
          DEFAULT_FORWARD_POLICY="ACCEPT"
        marker: "# {mark} KUBERNETES FORWARD POLICY"
        create: yes
      when: ufw_enabled
      
    - name: Add Kubernetes NAT rules to UFW
      blockinfile:
        path: /etc/ufw/before.rules
        block: |
          *nat
          :POSTROUTING ACCEPT [0:0]
          -A POSTROUTING -s 10.244.0.0/16 -o {{ ansible_default_ipv4.interface }} -j MASQUERADE
          COMMIT
        marker: "# {mark} KUBERNETES NAT"
        insertafter: "*filter"
        create: yes
      when: ufw_enabled
      
    - name: Enable IP forwarding in UFW
      blockinfile:
        path: /etc/ufw/sysctl.conf
        block: |
          net/ipv4/ip_forward=1
        marker: "# {mark} KUBERNETES IP FORWARD"
        create: yes
      when: ufw_enabled
      
    - name: Configure UFW rules for Kubernetes
      ufw:
        rule: allow
        port: "{{ item }}"
        proto: tcp
      loop:
        - "6443"  # Kubernetes API server
        - "2379"  # etcd
        - "2380"  # etcd peer
        - "10250" # kubelet
        - "10251" # kube-scheduler
        - "10252" # kube-controller-manager
        - "10255" # kubelet read-only
        - "30000:32767" # NodePort range
      when: ufw_enabled
      
    - name: Allow SSH
      ufw:
        rule: allow
        port: "22"
        proto: tcp
      when: ufw_enabled
      
    - name: Allow HTTP/HTTPS for NodePort services
      ufw:
        rule: allow
        port: "{{ item }}"
        proto: tcp
      loop:
        - "80"
        - "443"
      when: ufw_enabled
      
    - name: Enable UFW if requested
      ufw:
        state: enabled
        policy: allow
      when: ufw_enabled
      
    - name: Post-UFW connectivity test
      shell: kubectl -n spark exec pod/test-dns -- sh -c 'nc -vz 10.96.0.1 443 >/dev/null 2>&1 && echo ok || echo fail'
      register: post_ufw_test
      when: ufw_enabled
      
    - name: Fail if connectivity broken after UFW
      fail:
        msg: "Pod connectivity broken after UFW enable. Check UFW rules."
      when: ufw_enabled and post_ufw_test.stdout != "ok"
```

## Usage

1. **Test current connectivity first:**
   ```bash
   ansible-playbook -i ansible/inventory.yml ansible/playbooks/k8s/setup_network.yml
   ```

2. **Enable UFW when ready:**
   ```bash
   ansible-playbook -i ansible/inventory.yml ansible/playbooks/k8s/enable_ufw.yml -e "ufw_enabled=true"
   ```

## Troubleshooting

If pod connectivity breaks after enabling UFW:

1. **Check UFW status:**
   ```bash
   sudo ufw status verbose
   ```

2. **Check UFW logs:**
   ```bash
   sudo tail -f /var/log/ufw.log
   ```

3. **Disable UFW temporarily:**
   ```bash
   sudo ufw disable
   ```

4. **Check iptables rules:**
   ```bash
   sudo iptables -L FORWARD -n -v
   sudo iptables -t nat -L POSTROUTING -n -v
   ```

## Important Notes

- **DEFAULT_FORWARD_POLICY="ACCEPT"** is critical for pod-to-Service connectivity
- **NAT MASQUERADE** rules are needed for pod egress traffic
- **IP forwarding** must be enabled in UFW sysctl configuration
- Test connectivity before and after enabling UFW
- Monitor logs for any blocked traffic
