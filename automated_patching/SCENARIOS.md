# Auto Patch Script - Scenarios and Behavior

## Flag Usage

### WebLogic Flag (`-w`)
**Validates ONLY**: WebLogic patch ID and version
- **Format**: `-w [patch_id] [version]`
- **Example**: `-w 38412437 12.2.1.4.250910`
- **What it validates**:
  1. WebLogic patch number (38412437) from `opatch lspatches`
  2. WebLogic version (12.2.1.4.250910) from patch description

### Coherence Flag (`-c`)
**Validates**: Coherence patch ID and WebLogic ID (from inventory)
- **Format**: `-c [coherence_patch_id] [weblogic_id]`
- **Example**: `-c 1221427 38409281`
- **What it validates**:
  1. Coherence patch number (1221427) from `opatch lspatches`
  2. WebLogic ID (38409281) from `opatch lsinventory | grep <id>`

### Kernel Flag (`-r` or `-o`)
**Validates**: Kernel version (installed and applied)
- **Format**: `-r [kernel_version]`
- **Example**: `-r 4.18.0-553.87.1.el8_10.x86_64`
- **What it validates**:
  1. Installed kernel (from `grubby --default-kernel`)
  2. Current running kernel (from `uname -r`)

## Important Note

**WebLogic and Coherence patches are ALWAYS applied together** via `puppet agent -t`. This means:
- When you install WebLogic patches, Coherence patches are also installed
- When you install Coherence patches, WebLogic patches are also installed
- The installation command is the same for both

## Scenarios

### Scenario 1: Checking Only WebLogic (`-w`) - Not Found

**Command**: `./auto_patch.sh -w 38412437 12.2.1.4.250910`

**What happens**:
1. ✅ Validates WebLogic patch ID (38412437) - **FAILS** (not found)
2. ✅ Validates WebLogic version (12.2.1.4.250910) - **FAILS** (not found)
3. ⚠️ Shows: "WebLogic validation failed. Proceeding with patch installation..."
4. 🔧 **Installs patches via puppet agent** (this installs BOTH WebLogic AND Coherence)
5. ✅ Re-validates WebLogic patches
6. ✅ Shows: "WebLogic patches are installed successfully!"

**Result**: Both WebLogic and Coherence patches are installed (even though you only checked WebLogic)

---

### Scenario 2: Checking Only Coherence (`-c`) - Not Found

**Command**: `./auto_patch.sh -c 1221427 38409281`

**What happens**:
1. ✅ Validates Coherence patch ID (1221427) - **FAILS** (not found)
2. ✅ Validates WebLogic ID (38409281) - **FAILS** (not found)
3. ⚠️ Shows: "Coherence validation failed. Proceeding with patch installation..."
4. 🔧 **Installs patches via puppet agent** (this installs BOTH WebLogic AND Coherence)
5. ✅ Re-validates Coherence patches
6. ✅ Shows: "Coherence patches are installed successfully!"

**Result**: Both WebLogic and Coherence patches are installed (even though you only checked Coherence)

---

### Scenario 3: Checking Both (`-w` and `-c`) - Both Not Found

**Command**: `./auto_patch.sh -w 38412437 12.2.1.4.250910 -c 1221427 38409281`

**What happens**:
1. **WebLogic validation**:
   - ✅ Validates WebLogic patch ID - **FAILS**
   - ✅ Validates WebLogic version - **FAILS**
   - ⚠️ Shows: "WebLogic validation failed. Proceeding with patch installation..."
   - 🔧 **Installs patches via puppet agent** (installs BOTH)
   - ✅ Re-validates WebLogic - **PASSES**
   - ✅ Shows: "WebLogic patches are installed successfully!"

2. **Coherence validation**:
   - ✅ Validates Coherence patch ID - **PASSES** (already installed from step 1)
   - ✅ Validates WebLogic ID - **PASSES** (already installed from step 1)
   - ✅ Shows: "Coherence patches are already up to date. No installation needed."

**Result**: Both patches are installed. WebLogic installation happens first, which also installs Coherence, so Coherence validation passes without additional installation.

---

### Scenario 4: Checking Only RHEL (`-r`) - Not Installed

**Command**: `./auto_patch.sh -r 4.18.0-553.87.1.el8_10.x86_64`

**What happens**:
1. ✅ Checks installed kernel (from `grubby`) - **FAILS** (doesn't match)
2. ✅ Checks current kernel (from `uname -r`) - **FAILS** (doesn't match)
3. ⚠️ Shows: "Kernel validation failed. Proceeding with patch installation..."
4. 🔧 **Installs kernel patches** via installation script
5. ✅ Verifies installation:
   - Installed kernel matches expected ✅
   - Current kernel doesn't match (needs reboot) ⚠️
6. ✅ Shows: "RHEL kernel patch is installed successfully!"
7. ⚠️ Shows: "Please reboot the server to apply the patch."

**Result**: Kernel patches are installed. Reboot is required to apply them.

---

### Scenario 5: Checking Only WebLogic (`-w`) - Already Up to Date

**Command**: `./auto_patch.sh -w 38412437 12.2.1.4.250910`

**What happens**:
1. ✅ Validates WebLogic patch ID (38412437) - **PASSES**
2. ✅ Validates WebLogic version (12.2.1.4.250910) - **PASSES**
3. ✅ Shows: "All WebLogic patches are up to date"
4. ✅ Shows: "WebLogic patches are already up to date. No installation needed."
5. 🛑 **Script stops** (no installation)

**Result**: No installation needed. Script exits successfully.

---

### Scenario 6: Checking Only Coherence (`-c`) - Already Up to Date

**Command**: `./auto_patch.sh -c 1221427 38409281`

**What happens**:
1. ✅ Validates Coherence patch ID (1221427) - **PASSES**
2. ✅ Validates WebLogic ID (38409281) - **PASSES**
3. ✅ Shows: "All Coherence patches are up to date"
4. ✅ Shows: "Coherence patches are already up to date. No installation needed."
5. 🛑 **Script stops** (no installation)

**Result**: No installation needed. Script exits successfully.

---

### Scenario 7: Checking Only RHEL (`-r`) - Already Up to Date

**Command**: `./auto_patch.sh -r 4.18.0-553.87.1.el8_10.x86_64`

**What happens**:
1. ✅ Checks installed kernel (from `grubby`) - **PASSES** (matches)
2. ✅ Checks current kernel (from `uname -r`) - **PASSES** (matches)
3. ✅ Shows: "RHEL kernel patch is up to date and applied"
4. ✅ Shows: "RHEL kernel patch is up to date. No installation needed."
5. 🛑 **Script stops** (no installation)

**Result**: No installation needed. Script exits successfully.

---

### Scenario 8: Checking Only RHEL (`-r`) - Installed But Not Applied

**Command**: `./auto_patch.sh -r 4.18.0-553.87.1.el8_10.x86_64`

**What happens**:
1. ✅ Checks installed kernel (from `grubby`) - **PASSES** (matches expected)
2. ⚠️ Checks current kernel (from `uname -r`) - **FAILS** (doesn't match)
3. ⚠️ Shows: "RHEL kernel patch is installed but not applied"
4. ⚠️ Shows: "Please reboot the server to apply the patch"
5. 🛑 **Script stops** (no installation, patch already installed)

**Result**: Patch is installed but needs reboot. No installation performed.

---

## Summary Table

| Scenario | Flag Used | Validation Result | Installation | What Gets Installed |
|----------|-----------|-------------------|--------------|---------------------|
| WebLogic not found | `-w` | ❌ Fails | ✅ Yes | WebLogic + Coherence |
| Coherence not found | `-c` | ❌ Fails | ✅ Yes | WebLogic + Coherence |
| Both not found | `-w -c` | ❌ Both fail | ✅ Yes | WebLogic + Coherence (once) |
| WebLogic up to date | `-w` | ✅ Passes | ❌ No | Nothing |
| Coherence up to date | `-c` | ✅ Passes | ❌ No | Nothing |
| RHEL not installed | `-r` | ❌ Fails | ✅ Yes | Kernel patches |
| RHEL up to date | `-r` | ✅ Passes | ❌ No | Nothing |
| RHEL installed, not applied | `-r` | ⚠️ Partial | ❌ No | Nothing (needs reboot) |

## Key Points

1. **WebLogic and Coherence are always installed together** - Even if you only check one, both get installed
2. **Early exit on success** - If validation passes, script stops immediately
3. **RHEL has two states** - Installed (grubby) and Applied (uname -r)
4. **No redundant installations** - If both `-w` and `-c` are used and WebLogic installs first, Coherence validation will pass without additional installation

