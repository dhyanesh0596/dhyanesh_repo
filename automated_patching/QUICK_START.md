# Auto Patch Script - Quick Start Guide

## Installation

1. Ensure the script is executable:
   ```bash
   chmod +x auto_patch.sh
   ```

2. Verify you have root access (script will check automatically)

3. That's it! The script is completely standalone.

## Basic Usage

### Show Help
```bash
./auto_patch.sh -h
```

### Process WebLogic Only
```bash
./auto_patch.sh -w 38412437 12.2.1.4.250910 38409281 -v
```

### Process Coherence Only
```bash
./auto_patch.sh -c 1221427 -v
```

### Process Kernel Only
```bash
./auto_patch.sh -r 4.18.0-553.87.1.el8_10.x86_64 -v
```

## All Flag Examples

### WebLogic Flag (`-w`)

**Validates ONLY**: WebLogic patch ID and version

```bash
# With patch number and version
./auto_patch.sh -w 38412437 12.2.1.4.250910

# With patch number only
./auto_patch.sh -w 38412437
```

### Coherence Flag (`-c`)

**Validates**: Coherence patch ID and WebLogic ID (from inventory)

```bash
# With Coherence patch number and WebLogic ID
./auto_patch.sh -c 1221427 38409281

# With Coherence patch number only
./auto_patch.sh -c 1221427
```

### Kernel Flag (`-r` or `-o`)

```bash
# With kernel version
./auto_patch.sh -r 4.18.0-553.87.1.el8_10.x86_64

# Or using -o alias
./auto_patch.sh -o 4.18.0-553.87.1.el8_10.x86_64

# With defaults (if configured in script)
./auto_patch.sh -r
```

### Verbose Flag (`-v`)

Add `-v` to any command for detailed output:
```bash
./auto_patch.sh -w 38412437 12.2.1.4.250910 38409281 -v
./auto_patch.sh -c 1221427 -v
./auto_patch.sh -r 4.18.0-553.87.1.el8_10.x86_64 -v
```

## Combined Examples

### Process Multiple Types

```bash
# WebLogic and Coherence
./auto_patch.sh -w 38412437 12.2.1.4.250910 38409281 -c 1221427 -v

# WebLogic and Kernel
./auto_patch.sh -w 38412437 12.2.1.4.250910 38409281 -r 4.18.0-553.87.1.el8_10.x86_64 -v

# Coherence and Kernel
./auto_patch.sh -c 1221427 -r 4.18.0-553.87.1.el8_10.x86_64 -v

# All three types
./auto_patch.sh -w 38412437 12.2.1.4.250910 -c 1221427 38409281 -r 4.18.0-553.87.1.el8_10.x86_64 -v
```

## Understanding Values

### WebLogic Values (2 values for `-w`)

1. **Patch Number**: From `opatch lspatches` output
   - Example: `38412437` (from "38412437;WLS PATCH SET UPDATE...")

2. **Version**: From patch description
   - Example: `12.2.1.4.250910` (from "WLS PATCH SET UPDATE 12.2.1.4.250910")

### Coherence Values (2 values for `-c`)

1. **Coherence Patch Number**: From `opatch lspatches` output
   - Example: `1221427` (from "1221427;Coherence Cumulative Patch...")

2. **WebLogic ID**: From `opatch lsinventory | grep <id>` output
   - Example: `38409281` (from comma-separated list)

### Kernel Value (1 value for `-r` or `-o`)

- **Kernel Version**: Full kernel version string
  - Example: `4.18.0-553.87.1.el8_10.x86_64`
  - Find with: `grubby --default-kernel`

## Typical Workflows

### 1. First Time - Check Everything
```bash
./auto_patch.sh -w 38412437 12.2.1.4.250910 38409281 -c 1221427 -r 4.18.0-553.87.1.el8_10.x86_64 -v
```

### 2. Monthly - Kernel Only
```bash
./auto_patch.sh -r 4.18.0-553.87.1.el8_10.x86_64 -v
```

### 3. Quarterly - WebLogic/Coherence
```bash
./auto_patch.sh -w 38412437 12.2.1.4.250910 -c 1221427 38409281 -v
```

### 4. Testing Specific Patches
```bash
# Test WebLogic only
./auto_patch.sh -w 38412437 12.2.1.4.250910 -v

# Test Coherence only
./auto_patch.sh -c 1221427 38409281 -v
```

## Understanding Output

### ✅ Success (Validation Passed - Script Stops)

```
[SUCCESS] All WebLogic patches are up to date
[SUCCESS] WebLogic patches are already up to date. No installation needed.
```

### ✅ Success (After Installation)

```
[SUCCESS] WebLogic patches are installed successfully!
[SUCCESS] Coherence patches are installed successfully!
[SUCCESS] RHEL kernel patch is installed and applied successfully!
```

### ⚠️ Kernel Installed But Not Applied

```
[WARNING] RHEL kernel patch is installed but not applied
[INFO] Installed kernel: 4.18.0-553.87.1.el8_10.x86_64
[INFO] Current kernel: 4.18.0-553.78.1.el8_10.x86_64
[WARNING] Please reboot the server to apply the patch
```

### ❌ Failure

```
[ERROR] WebLogic patch validation failed after installation
[ERROR] Some patches failed. Please review the output above.
```

## Important Notes

1. **Script stops if validation passes**: No installation needed
2. **WebLogic validates only patch ID and version**: `-w` flag validates WebLogic patch number and version only
3. **Coherence validates patch ID and WebLogic ID**: `-c` flag validates Coherence patch number and WebLogic ID from inventory
4. **WebLogic and Coherence are always installed together**: Even if you only check one, both get installed via puppet agent
5. **Kernel validation is smart**: Checks both installed (grubby) and applied (uname -r)
6. **No hardcoded values**: All values come from flags or script configuration
7. **Verbose recommended**: Use `-v` to see what's happening

## Important Scenarios

- **Checking only WebLogic (`-w`) and it's not found**: Installs both WebLogic and Coherence
- **Checking only Coherence (`-c`) and it's not found**: Installs both WebLogic and Coherence
- **Checking both (`-w` and `-c`) and both not found**: Installs both (once via puppet)
- **Checking only RHEL (`-r`) and it's not installed**: Installs kernel patches

See `SCENARIOS.md` for detailed explanations of all scenarios.

## Configuration

Edit the top of `auto_patch.sh` to set defaults:

```bash
# WebLogic/Coherence Configuration
DEFAULT_WEBLOGIC_PATCH="38412437"
DEFAULT_WEBLOGIC_VERSION="12.2.1.4.250910"
DEFAULT_WEBLOGIC_ID="38409281"
DEFAULT_COHERENCE_PATCH="1221427"

# Kernel Configuration
DEFAULT_KERNEL_VERSION="4.18.0-553.87.1.el8_10.x86_64"
```

Then you can use:
```bash
./auto_patch.sh -w -c -r -v
```

## Next Steps

- Read `README.md` for complete documentation
- Check script comments for detailed function descriptions
- Modify default values at the top of the script as needed

## Getting Help

```bash
./auto_patch.sh -h
```

For detailed help, see:
- `README.md` - Complete documentation
- `SCENARIOS.md` - Detailed scenario explanations
- Script header comments - Function descriptions
