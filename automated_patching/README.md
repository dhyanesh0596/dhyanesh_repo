# Automated Patch Management Script - Standalone Version

## Overview

The `auto_patch.sh` script is a **completely standalone** automated patch management tool that validates, installs, and re-validates patches for WebLogic, Coherence, and RHEL/Kernel systems. This script has **no external dependencies** - everything is self-contained in a single file.

## Key Features

- **100% Standalone**: No dependencies on other scripts or toolkits - everything is in one file
- **Automated Workflow**: Validates → Installs → Re-validates patches automatically
- **Early Exit**: If validation passes, script stops (no installation needed)
- **Separate Flags**: WebLogic (`-w`), Coherence (`-c`), and Kernel (`-r`/`-o`) can be processed independently
- **Version Validation**: Validates WebLogic version from patch description (e.g., 12.2.1.4.250910)
- **Smart Kernel Validation**: Checks both installed (grubby) and applied (uname -r) kernel versions
- **Case-Insensitive Flags**: All flags work regardless of case
- **Verbose Mode**: Detailed step-by-step output with `-v` flag

## Quick Start

```bash
# Process WebLogic only
./auto_patch.sh -w 38412437 12.2.1.4.250910 38409281

# Process Coherence only
./auto_patch.sh -c 1221427

# Process Kernel only
./auto_patch.sh -r 4.18.0-553.87.1.el8_10.x86_64

# Process all with verbose
./auto_patch.sh -w 38412437 12.2.1.4.250910 38409281 -c 1221427 -r 4.18.0-553.87.1.el8_10.x86_64 -v
```

## Usage

### Basic Syntax

```bash
./auto_patch.sh [OPTIONS]
```

### Options

| Flag | Long Form | Description | Value Format |
|------|-----------|-------------|--------------|
| `-w` | `--weblogic` | Process WebLogic patches | Optional: 3 values in order: patch number, version, ID |
| `-c` | `--coherence` | Process Coherence patches separately | Optional: patch number |
| `-r` | `--rhel` | Process RHEL/Kernel patches | Optional: kernel version |
| `-o` | `--kernel` | Alias for `-r` (same as RHEL/Kernel) | Optional: kernel version |
| `-v` | `--verbose` | Enable verbose output | No value |
| `-h` | `--help` | Show help message | No value |

### WebLogic Flag (`-w`)

The `-w` flag validates **ONLY** WebLogic patch ID and version (not WebLogic ID from inventory).

**Accepts 2 values in order**:
1. **WebLogic Patch Number**: From `opatch lspatches` (e.g., `38412437`)
2. **WebLogic Version**: From patch description (e.g., `12.2.1.4.250910`)

**Examples**:
```bash
# Provide patch number only
./auto_patch.sh -w 38412437

# Provide patch number and version
./auto_patch.sh -w 38412437 12.2.1.4.250910
```

### Coherence Flag (`-c`)

The `-c` flag validates Coherence patch ID and WebLogic ID (from inventory).

**Accepts 2 values in order**:
1. **Coherence Patch Number**: From `opatch lspatches` (e.g., `1221427`)
2. **WebLogic ID**: From `opatch lsinventory | grep <id>` (e.g., `38409281`)

**Examples**:
```bash
# Provide Coherence patch number only
./auto_patch.sh -c 1221427

# Provide both Coherence patch number and WebLogic ID
./auto_patch.sh -c 1221427 38409281
```

### Kernel Flag (`-r` or `-o`)

The `-r` or `-o` flag accepts an optional kernel version:

**Examples**:
```bash
# Use default value (if configured)
./auto_patch.sh -r

# Provide specific kernel version
./auto_patch.sh -r 4.18.0-553.87.1.el8_10.x86_64
```

## Complete Examples

### Example 1: WebLogic Only

```bash
./auto_patch.sh -w 38412437 12.2.1.4.250910 -v
```

**What it does**:
1. Validates WebLogic patch number `38412437` from `lspatches`
2. Validates WebLogic version `12.2.1.4.250910` from patch description
3. If both pass → Success, stops (no installation)
4. If any fail → Installs patches via puppet (installs BOTH WebLogic and Coherence), then re-validates

### Example 2: Coherence Only

```bash
./auto_patch.sh -c 1221427 38409281 -v
```

**What it does**:
1. Validates Coherence patch number `1221427` from `lspatches`
2. Validates WebLogic ID `38409281` from `lsinventory`
3. If both pass → Success, stops (no installation)
4. If any fail → Installs patches via puppet (installs BOTH WebLogic and Coherence), then re-validates

### Example 3: Kernel Only

```bash
./auto_patch.sh -r 4.18.0-553.87.1.el8_10.x86_64 -v
```

**What it does**:
1. Checks installed kernel (from `grubby --default-kernel`)
2. Checks current kernel (from `uname -r`)
3. If both match expected → "Up to date", stops
4. If installed but not applied → "Installed but not applied, reboot needed"
5. If not installed → Installs patches, then verifies

### Example 4: All Patches Together

```bash
./auto_patch.sh -w 38412437 12.2.1.4.250910 -c 1221427 38409281 -r 4.18.0-553.87.1.el8_10.x86_64 -v
```

**What it does**:
- Processes WebLogic (patch ID + version), Coherence (patch ID + WebLogic ID), and Kernel patches
- Shows verbose output for each
- Reports success/failure for each
- **Note**: If WebLogic installs first, Coherence validation may pass without additional installation (they're applied together)

### Example 5: Using Defaults (If Configured)

```bash
# Edit script to set defaults, then:
./auto_patch.sh -w -c -r -v
```

## How It Works

### WebLogic Workflow

1. **Validation**:
   - Runs `opatch lspatches` → validates patch number (e.g., `38412437`)
   - Validates version in patch description (e.g., `12.2.1.4.250910`)
   - Runs `opatch lsinventory | grep <id>` → validates ID (e.g., `38409281`)
   - **If all pass → Success message, script stops**
   - If any fail → Proceed to installation

2. **Installation**:
   - Stops WebLogic processes
   - Removes puppet fact file
   - Runs `puppet agent -t`

3. **Re-validation**:
   - Re-runs all validation checks
   - Reports "patches are installed successfully!"

### Coherence Workflow

1. **Validation**:
   - Runs `opatch lspatches` → validates patch number (e.g., `1221427`)
   - **If passes → Success message, script stops**
   - If fails → Proceed to installation

2. **Installation**:
   - Same as WebLogic (they're applied together via puppet)

3. **Re-validation**:
   - Re-validates patch number
   - Reports "patches are installed successfully!"

### Kernel Workflow

1. **Validation**:
   - Gets installed kernel from `grubby --default-kernel`
   - Gets current kernel from `uname -r`
   - Compares both with expected version
   - **If both match → "Up to date", script stops**
   - **If installed but current doesn't match → "Installed but not applied, reboot needed"**
   - If not installed → Proceed to installation

2. **Installation**:
   - Executes kernel patch installation script

3. **Verification**:
   - Checks installed kernel (grubby)
   - Checks current kernel (uname -r)
   - Reports status:
     - "Installed and applied successfully!" (both match)
     - "Installed successfully! Please reboot to apply" (installed but not applied)

## Finding Patch Values

### Finding WebLogic Patch Number and Version

Run as weblogic user:
```bash
su - weblogic
bash /opt/bt/weblogic/OPatch/opatch lspatches
```

Example output:
```
38412437;WLS PATCH SET UPDATE 12.2.1.4.250910
1221427;Coherence Cumulative Patch 12.2.1.4.27
OPatch succeeded.
```

- WebLogic patch number: `38412437`
- WebLogic version: `12.2.1.4.250910` (from description)
- Coherence patch number: `1221427`

### Finding WebLogic ID

Run as weblogic user:
```bash
su - weblogic
bash /opt/bt/weblogic/OPatch/opatch lsinventory | grep 38409281
```

Example output:
```
37588807, 37658278, 37664985, 38018956, 38312713, 38409281
```

- WebLogic ID: `38409281` (one of the IDs in the comma-separated list)

### Finding Kernel Version

```bash
# Check installed kernel (what will boot)
grubby --default-kernel
# Output: /boot/vmlinuz-4.18.0-553.87.1.el8_10.x86_64
# Use: 4.18.0-553.87.1.el8_10.x86_64

# Check current running kernel
uname -r
# Output: 4.18.0-553.87.1.el8_10.x86_64
```

## Configuration

All configuration is at the top of the script (lines ~30-45). You can modify:

- **WebLogic defaults**: `DEFAULT_WEBLOGIC_PATCH`, `DEFAULT_WEBLOGIC_VERSION`, `DEFAULT_WEBLOGIC_ID`
- **Coherence defaults**: `DEFAULT_COHERENCE_PATCH`
- **Kernel defaults**: `DEFAULT_KERNEL_VERSION`
- **Paths**: `WEBLOGIC_USER`, `OPATCH_PATH`, `PUPPET_FACT_FILE`, `KERNEL_INSTALL_SCRIPT`, `KERNEL_INSTALL_DIR`

**Note**: If defaults are empty, you must provide values via flags.

## Output Messages

### Success Messages

**WebLogic/Coherence**:
- `"WebLogic patches are already up to date. No installation needed."` (validation passed)
- `"WebLogic patches are installed successfully!"` (after installation and re-validation)

**Kernel**:
- `"RHEL kernel patch is up to date and applied"` (both installed and applied)
- `"RHEL kernel patch is installed but not applied. Please reboot the server to apply the patch."` (installed, needs reboot)
- `"RHEL kernel patch is installed and applied successfully!"` (after installation)

### Failure Messages

- `"Some patches failed. Please review the output above."` (overall failure)
- Individual validation failures are shown for each check

## Exit Codes

- `0`: All selected patches processed successfully
- `1`: One or more patches failed

## Requirements

- Root privileges (script checks automatically)
- `grubby` command (for kernel validation)
- `puppet` command (for WebLogic/Coherence installation)
- Access to OPatch at `/opt/bt/weblogic/OPatch/opatch`
- `weblogic` user must exist (for OPatch commands)

## Troubleshooting

### "No patches selected" Error

**Problem**: No flags provided  
**Solution**: Specify at least one patch type: `-w`, `-c`, or `-r`

### Validation Passes But Script Continues

**Problem**: Script should stop if validation passes  
**Solution**: This is correct behavior - script stops after showing success message

### Kernel "Installed but not applied"

**Problem**: Kernel patch installed but not applied  
**Solution**: This is normal - reboot the server to apply the patch

### "Patch number is required" Error

**Problem**: No patch number provided and no default configured  
**Solution**: Provide patch number via flag or set default in script configuration

## Best Practices

1. **Always use verbose mode first**: Run with `-v` to understand what the script is doing
2. **Test with one patch type**: Start with `-w`, `-c`, or `-r` before combining
3. **Verify patch values**: Ensure patch numbers/versions are correct before running
4. **Check logs**: Review output for any warnings or errors
5. **Backup before patching**: Always have backups before running patch installations
6. **Schedule appropriately**: Kernel patches require reboot; plan accordingly

## Important Scenarios

See `SCENARIOS.md` for detailed explanations of what happens in each scenario:

- Checking only WebLogic when not found → Installs both WebLogic and Coherence
- Checking only Coherence when not found → Installs both WebLogic and Coherence
- Checking both when both not found → Installs both (once)
- Checking only RHEL when not installed → Installs kernel patches
- All "up to date" scenarios → Script stops immediately

**Key Point**: WebLogic and Coherence are always applied together via puppet agent, regardless of which flag you use.

## Version

**Version**: 1.0 (Standalone)  
**Last Updated**: Updated with separate Coherence flag, version validation, and scenario documentation  
**Dependencies**: None (100% standalone)
