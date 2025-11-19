# Available GPU Metrics

This document lists all GPU metrics available for collection from AMD Radeon RX 7600M XT GPUs via the amdgpu driver's sysfs interface, categorized by availability level.

## Metric Categories

- **Generic**: Available across GPUs from all manufacturers (NVIDIA, AMD, Intel, etc.)
- **AMD-Specific**: Available across AMD GPUs via the amdgpu driver
- **Device-Specific**: Unique to the RX 7600M XT model (specific hardware values)

---

## Complete Metrics Table

### Utilization Metrics

| Metric | Field Name (Generic) | Field Name (AMD) | Field Name (Device) | Category | Source (sysfs) | Currently Collected |
|--------|---------------------|------------------|---------------------|----------|----------------|---------------------|
| GPU Core Utilization % | `gpu.utilization.core_percent` | - | - | Generic | `/sys/class/drm/card*/device/gpu_busy_percent` | ✅ Yes |
| VRAM Utilization % | `gpu.utilization.memory_percent` | - | - | Generic | `/sys/class/drm/card*/device/mem_busy_percent` | ✅ Yes |
| GPU Activity | `gpu.utilization.active` | - | - | Generic | Derived from utilization | ❌ No |

### Temperature Metrics

| Metric | Field Name (Generic) | Field Name (AMD) | Field Name (Device) | Category | Source (sysfs) | Currently Collected |
|--------|---------------------|------------------|---------------------|----------|----------------|---------------------|
| Edge Temperature | `gpu.temperature_c.edge` | - | - | Generic | `/sys/class/drm/card*/device/hwmon/hwmon*/temp1_input` | ✅ Yes |
| Junction Temperature (Hotspot) | `gpu.temperature_c.junction` | `amd.gpu.temperature_c.hotspot` | - | AMD-Specific | `/sys/class/drm/card*/device/hwmon/hwmon*/temp2_input` | ❌ No |
| Memory Junction Temperature | `gpu.temperature_c.memory` | `amd.gpu.temperature_c.memory_junction` | - | AMD-Specific | `/sys/class/drm/card*/device/hwmon/hwmon*/temp3_input` | ❌ No |
| Temperature Min | `gpu.temperature_c.min` | - | - | Generic | `/sys/class/drm/card*/device/hwmon/hwmon*/temp*_min` | ❌ No |
| Temperature Max | `gpu.temperature_c.max` | - | - | Generic | `/sys/class/drm/card*/device/hwmon/hwmon*/temp*_max` | ❌ No |
| Temperature Critical | `gpu.temperature_c.critical` | - | - | Generic | `/sys/class/drm/card*/device/hwmon/hwmon*/temp*_crit` | ❌ No |

### Power Metrics

| Metric | Field Name (Generic) | Field Name (AMD) | Field Name (Device) | Category | Source (sysfs) | Currently Collected |
|--------|---------------------|------------------|---------------------|----------|----------------|---------------------|
| Average Power | `gpu.power.watts` | - | - | Generic | `/sys/class/drm/card*/device/hwmon/hwmon*/power1_average` | ✅ Yes |
| Current Power | `gpu.power.watts_current` | - | - | Generic | `/sys/class/drm/card*/device/hwmon/hwmon*/power1_input` | ❌ No |
| Power Cap | `gpu.power.cap_watts` | - | - | Generic | `/sys/class/drm/card*/device/hwmon/hwmon*/power1_cap` | ❌ No |
| Power Cap Max | `gpu.power.cap_max_watts` | - | - | Generic | `/sys/class/drm/card*/device/hwmon/hwmon*/power1_cap_max` | ❌ No |
| Power Cap Min | `gpu.power.cap_min_watts` | - | - | Generic | `/sys/class/drm/card*/device/hwmon/hwmon*/power1_cap_min` | ❌ No |

### Clock Speed Metrics

| Metric | Field Name (Generic) | Field Name (AMD) | Field Name (Device) | Category | Source (sysfs) | Currently Collected |
|--------|---------------------|------------------|---------------------|----------|----------------|---------------------|
| Graphics Clock (Current) | `gpu.clocks.core_mhz` | - | - | Generic | `/sys/class/drm/card*/device/hwmon/hwmon*/freq1_input` | ✅ Yes (as `gfx_mhz`) |
| Memory Clock (Current) | `gpu.clocks.memory_mhz` | - | - | Generic | `/sys/class/drm/card*/device/hwmon/hwmon*/freq2_input` | ✅ Yes |
| Graphics Clock (Min) | `gpu.clocks.core_min_mhz` | - | - | Generic | `/sys/class/drm/card*/device/hwmon/hwmon*/freq1_min` | ❌ No |
| Graphics Clock (Max) | `gpu.clocks.core_max_mhz` | - | - | Generic | `/sys/class/drm/card*/device/hwmon/hwmon*/freq1_max` | ❌ No |
| Memory Clock (Min) | `gpu.clocks.memory_min_mhz` | - | - | Generic | `/sys/class/drm/card*/device/hwmon/hwmon*/freq2_min` | ❌ No |
| Memory Clock (Max) | `gpu.clocks.memory_max_mhz` | - | - | Generic | `/sys/class/drm/card*/device/hwmon/hwmon*/freq2_max` | ❌ No |

### Fan Metrics

| Metric | Field Name (Generic) | Field Name (AMD) | Field Name (Device) | Category | Source (sysfs) | Currently Collected |
|--------|---------------------|------------------|---------------------|----------|----------------|---------------------|
| Fan Speed (RPM) | `gpu.fan.rpm` | - | - | Generic | `/sys/class/drm/card*/device/hwmon/hwmon*/fan1_input` | ✅ Yes |
| Fan Speed (Min) | `gpu.fan.rpm_min` | - | - | Generic | `/sys/class/drm/card*/device/hwmon/hwmon*/fan1_min` | ❌ No |
| Fan Speed (Max) | `gpu.fan.rpm_max` | - | - | Generic | `/sys/class/drm/card*/device/hwmon/hwmon*/fan1_max` | ❌ No |

### Voltage Metrics

| Metric | Field Name (Generic) | Field Name (AMD) | Field Name (Device) | Category | Source (sysfs) | Currently Collected |
|--------|---------------------|------------------|---------------------|----------|----------------|---------------------|
| GPU Core Voltage | `gpu.voltage.core_v` | - | - | Generic | `/sys/class/drm/card*/device/hwmon/hwmon*/in0_input` | ❌ No |
| Memory Voltage | `gpu.voltage.memory_v` | - | - | Generic | Various voltage files | ❌ No |

### Hardware Identification Metrics

| Metric | Field Name (Generic) | Field Name (AMD) | Field Name (Device) | Category | Source (sysfs) | Currently Collected |
|--------|---------------------|------------------|---------------------|----------|----------------|---------------------|
| GPU Card Name | `gpu.card` | - | - | Generic | `/sys/class/drm/card*/name` | ✅ Yes |
| Vendor ID | `gpu.vendor.id` | - | - | Generic | `/sys/class/drm/card*/device/vendor` | ✅ Yes |
| Device ID | `gpu.device.id` | - | - | Generic | `/sys/class/drm/card*/device/device` | ✅ Yes |
| Subsystem Vendor | `gpu.device.subsystem_vendor` | - | - | Generic | `/sys/class/drm/card*/device/subsystem_vendor` | ✅ Yes |
| Subsystem Device | `gpu.device.subsystem_id` | - | - | Generic | `/sys/class/drm/card*/device/subsystem_device` | ✅ Yes |
| PCI Bus Address | `gpu.bus.address` | - | - | Generic | `/sys/class/drm/card*/device/uevent` | ✅ Yes |

### Hardware Specifications (Static - Device-Specific Values)

| Metric | Field Name (Generic) | Field Name (AMD) | Field Name (Device) | Category | Value (RX 7600M XT) |
|--------|---------------------|------------------|---------------------|----------|---------------------|
| Compute Units | `gpu.compute_units` | `amd.gpu.compute_units` | - | AMD-Specific | 32 |
| Shader Processors | `gpu.shader_processors` | `amd.gpu.shader_processors` | - | AMD-Specific | 2,048 |
| Texture Mapping Units | `gpu.tmu_count` | `amd.gpu.tmu_count` | - | AMD-Specific | 128 |
| Render Output Units | `gpu.rop_count` | `amd.gpu.rop_count` | - | AMD-Specific | 64 |
| Ray Accelerators | `gpu.ray_accelerators` | `amd.gpu.ray_accelerators` | - | AMD-Specific | 32 |
| Memory Size | `gpu.memory.size_bytes` | - | - | Generic | 8 GB (8,589,934,592 bytes) |
| Memory Type | `gpu.memory.type` | - | - | Generic | GDDR6 |
| Memory Bus Width | `gpu.memory.bus_width_bits` | - | - | Generic | 128-bit |
| Base Clock | `gpu.clocks.base_mhz` | - | - | Generic | 1,280 MHz |
| Boost Clock | `gpu.clocks.boost_mhz` | - | - | Generic | 2,469 MHz |
| Infinity Cache | `gpu.cache.size_bytes` | `amd.gpu.infinity_cache.size_bytes` | - | AMD-Specific | 32 MB (33,554,432 bytes) |
| TDP | `gpu.power.tdp_watts` | - | - | Generic | 75-120W |

### Compute Performance Metrics (Theoretical - Static)

| Metric | Field Name (Generic) | Field Name (AMD) | Field Name (Device) | Category | Value (RX 7600M XT) |
|--------|---------------------|------------------|---------------------|----------|---------------------|
| FP32 Performance | `gpu.performance.fp32_tflops` | `amd.gpu.performance.fp32_tflops` | - | AMD-Specific | 20.23 TFLOPS |
| FP16 Performance | `gpu.performance.fp16_tflops` | `amd.gpu.performance.fp16_tflops` | - | AMD-Specific | 40.45 TFLOPS |
| FP64 Performance | `gpu.performance.fp64_gflops` | `amd.gpu.performance.fp64_gflops` | - | AMD-Specific | 632.1 GFLOPS |
| INT8 Performance | `gpu.performance.int8_tops` | `amd.gpu.performance.int8_tops` | - | AMD-Specific | 40.45 TOPS |
| INT4 Performance | `gpu.performance.int4_tops` | `amd.gpu.performance.int4_tops` | - | AMD-Specific | 80.90 TOPS |

---

## Field Naming Conventions

### Generic Fields
- Use `gpu.*` prefix for metrics available across all GPU manufacturers
- Examples: `gpu.utilization.core_percent`, `gpu.temperature_c.edge`, `gpu.power.watts`

### AMD-Specific Fields
- Use `amd.gpu.*` prefix for metrics specific to AMD GPUs
- Examples: `amd.gpu.temperature_c.hotspot`, `amd.gpu.compute_units`, `amd.gpu.infinity_cache.size_bytes`

### Device-Specific Values
- Static hardware specifications are stored in the same field structure but with device-specific values
- The field name remains generic or AMD-specific, but the value is unique to the RX 7600M XT

---

## Metrics Not Available via sysfs

The following metrics require external tools or application-level monitoring:

| Metric | Availability | Tool Required |
|--------|--------------|---------------|
| Frame Rate (FPS) | Generic | Application-level monitoring |
| Frame Time | Generic | Application-level monitoring |
| VRAM Usage (Bytes) | Generic | `rocm-smi`, `nvidia-smi`, or similar |
| VRAM Total (Bytes) | Generic | `rocm-smi`, `nvidia-smi`, or similar |
| PCIe Link Speed | Generic | `lspci` |
| PCIe Link Width | Generic | `lspci` |
| Driver Version | Generic | `modinfo amdgpu` |
| Firmware Version | Generic | `dmesg` or `modinfo` |

---

## Summary by Category

### Generic Metrics (Available on most/all GPUs)
- Utilization: Core %, Memory %
- Temperature: Edge, Min, Max, Critical
- Power: Average, Current, Cap, Cap Min/Max
- Clocks: Core/Memory Current/Min/Max
- Fan: RPM, Min, Max
- Voltage: Core, Memory
- Hardware ID: Card, Vendor, Device, PCI info
- Memory: Size, Type, Bus Width
- Clocks: Base, Boost
- TDP

### AMD-Specific Metrics (Available via amdgpu driver)
- Temperature: Junction (Hotspot), Memory Junction
- Hardware: Compute Units, Shader Processors, TMUs, ROPs, Ray Accelerators
- Cache: Infinity Cache size
- Performance: FP32/FP16/FP64, INT8/INT4

### Device-Specific Values (RX 7600M XT)
- 32 Compute Units
- 2,048 Shader Processors
- 128 TMUs, 64 ROPs
- 32 Ray Accelerators
- 8 GB GDDR6 Memory
- 128-bit Memory Bus
- 32 MB Infinity Cache
- Base: 1,280 MHz, Boost: 2,469 MHz
- TDP: 75-120W
- 20.23 TFLOPS FP32, 40.45 TFLOPS FP16, 632.1 GFLOPS FP64

