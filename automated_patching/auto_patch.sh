#!/bin/bash

# Automated Patch Management Script - Standalone Version
# This script automatically validates, installs, and re-validates patches
#
# Usage: ./auto_patch.sh [-w [weblogic_patch] [weblogic_version] [weblogic_id]] [-c [coherence_patch]] [-r|-o [kernel_version]] [-v]
#
# Flags:
#   -w, --weblogic [weblogic_patch] [weblogic_version] [weblogic_id]
#       Process WebLogic patches
#       Optional values:
#         - weblogic_patch: Patch number from lspatches (e.g., 38412437)
#         - weblogic_version: Version from patch description (e.g., 12.2.1.4.250910)
#         - weblogic_id: Patch ID from lsinventory grep (e.g., 38409281)
#
#   -c, --coherence [coherence_patch]
#       Process Coherence patches separately
#       Optional: coherence_patch number from lspatches (e.g., 1221427)
#
#   -r, --rhel [kernel_version]     : Process RHEL/Kernel patches
#   -o, --kernel [kernel_version]   : Alias for -r (RHEL/Kernel patches)
#       Optional: specify kernel version (e.g., 4.18.0-553.87.1.el8_10.x86_64)
#
#   -v, --verbose                   : Enable verbose output showing each step
#   -h, --help                      : Show this help message

# ============================================================================
# CONFIGURATION - Modify these values as needed
# ============================================================================

# WebLogic/Coherence Configuration
WEBLOGIC_USER="weblogic"
OPATCH_PATH="/opt/bt/weblogic/OPatch/opatch"
PUPPET_FACT_FILE="/etc/puppetlabs/facter/facts.d/opatched.txt"

# Default patch values (used if not provided via flags)
DEFAULT_WEBLOGIC_PATCH=""
DEFAULT_WEBLOGIC_VERSION=""
DEFAULT_WEBLOGIC_ID=""
DEFAULT_COHERENCE_PATCH=""

# Kernel Configuration
KERNEL_INSTALL_SCRIPT="/root/scripts/install_repo_updates_cron.sh"
KERNEL_INSTALL_DIR="/root/scripts"
DEFAULT_KERNEL_VERSION=""

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

VERBOSE=false
PROCESS_WEBLOGIC=false
PROCESS_COHERENCE=false
PROCESS_KERNEL=false
WEBLOGIC_PATCH_NUMBER=""
WEBLOGIC_VERSION=""
WEBLOGIC_PATCH_ID=""
COHERENCE_PATCH_NUMBER=""
KERNEL_VERSION=""

# ============================================================================
# COLOR CODES AND LOGGING FUNCTIONS
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

vlog() {
    if [[ "$VERBOSE" == true ]]; then
        log_info "$1"
    fi
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Display header
display_header() {
    echo "=========================================="
    echo "Automated Patch Management"
    echo "=========================================="
    echo
}

# Show usage
show_usage() {
    cat << EOF
Automated Patch Management Script - Standalone Version
======================================================

This script automatically validates, installs, and re-validates patches.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -w, --weblogic [weblogic_patch] [weblogic_version]
        Process WebLogic patches ONLY
        Validates: WebLogic patch ID and version
        
        Optional values (in order):
        1. weblogic_patch: Patch number from 'opatch lspatches' 
           Example: 38412437 (from "38412437;WLS PATCH SET UPDATE...")
        
        2. weblogic_version: Version from patch description
           Example: 12.2.1.4.250910 (from "WLS PATCH SET UPDATE 12.2.1.4.250910")
    
    -c, --coherence [coherence_patch] [weblogic_id]
        Process Coherence patches separately
        Validates: Coherence patch ID and WebLogic ID (from inventory)
        
        Optional values (in order):
        1. coherence_patch: Patch number from 'opatch lspatches'
           Example: 1221427 (from "1221427;Coherence Cumulative Patch...")
        
        2. weblogic_id: WebLogic ID from 'opatch lsinventory | grep <id>'
           Example: 38409281 (found in comma-separated list during Coherence validation)
    
    -r, --rhel [kernel_version]     Process RHEL/Kernel patches
    -o, --kernel [kernel_version]   Alias for -r (same as RHEL/Kernel)
        Optional: specify kernel version
        Example: 4.18.0-553.87.1.el8_10.x86_64
    
    -v, --verbose                   Enable verbose output showing each step
    
    -h, --help                      Show this help message

EXAMPLES:
    # Process WebLogic only (patch ID and version)
    $0 -w 38412437 12.2.1.4.250910
    
    # Process Coherence only (patch ID and WebLogic ID)
    $0 -c 1221427 38409281
    
    # Process Kernel only
    $0 -r 4.18.0-553.87.1.el8_10.x86_64
    
    # Process all with verbose
    $0 -w 38412437 12.2.1.4.250910 -c 1221427 38409281 -r 4.18.0-553.87.1.el8_10.x86_64 -v

IMPORTANT SCENARIOS:
    - If checking only WebLogic (-w) and it's not found:
      → Installs patches via puppet agent (which also installs Coherence)
    
    - If checking only Coherence (-c) and it's not found:
      → Installs patches via puppet agent (which also installs WebLogic)
    
    - If checking both (-w and -c) and both are not found:
      → Installs patches via puppet agent (applies both together)
    
    - If checking only RHEL (-r) and it's not installed:
      → Installs kernel patches
    
    - WebLogic and Coherence are ALWAYS applied together via puppet agent,
      regardless of which flag you use

NOTES:
    - All flags are case-insensitive
    - If validation passes, script stops (no installation needed)
    - Script requires root privileges
    - Kernel patches require manual reboot after installation
    - Use 'uname -r' to check if kernel patch is applied
    - Use 'grubby --default-kernel' to check if kernel patch is installed

EOF
}

# Normalize flag (case-insensitive)
normalize_flag() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

# ============================================================================
# OPATCH FUNCTIONS
# ============================================================================

# Run OPatch command as weblogic user
run_opatch_as_weblogic() {
    local command=$1
    
    # Check if weblogic user exists
    if [[ -n "$WEBLOGIC_USER" ]] && ! id "$WEBLOGIC_USER" &>/dev/null; then
        log_error "User '$WEBLOGIC_USER' does not exist"
        return 1
    fi
    
    # Check if OPatch exists
    if [[ ! -f "$OPATCH_PATH" ]]; then
        log_error "OPatch not found at: $OPATCH_PATH"
        return 1
    fi
    
    # If running as root, switch to weblogic user
    if [[ $EUID -eq 0 ]] && [[ -n "$WEBLOGIC_USER" ]]; then
        su - "$WEBLOGIC_USER" -c "bash \"$OPATCH_PATH\" $command" 2>&1
    else
        bash "$OPATCH_PATH" $command 2>&1
    fi
}

# Get patches list from opatch lspatches
get_opatch_patches() {
    local raw_output=$(run_opatch_as_weblogic "lspatches")
    
    # Check for errors
    if echo "$raw_output" | grep -qi "The user is root\|cannot continue"; then
        return 1
    fi
    
    # Extract patch lines (format: "number;description")
    echo "$raw_output" | grep -v "OPatch succeeded" | grep -v "OPatch failed" | grep -v "error code" | grep -v "The user is root" | grep -v "^$" | grep -E "^[0-9]+"
}

# Validate patch in lspatches output
validate_patch_in_lspatches() {
    local patch_number=$1
    local patch_type=$2  # "weblogic" or "coherence"
    local patches_output=$(get_opatch_patches)
    
    if [[ -z "$patches_output" ]]; then
        log_error "Cannot retrieve patch list from OPatch"
        return 1
    fi
    
    vlog "Available patches from lspatches:"
    echo "$patches_output" | while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            vlog "  $line"
        fi
    done
    
    # Check if patch number exists
    if echo "$patches_output" | grep -qE "^${patch_number}(;|$|[[:space:]])"; then
        local found_patch=$(echo "$patches_output" | grep -E "^${patch_number}(;|$|[[:space:]])" | head -1)
        log_info "Found ${patch_type} patch: $found_patch"
        return 0
    else
        log_error "${patch_type^} patch validation FAILED"
        log_error "Expected patch number: $patch_number"
        log_error "Patch not found in lspatches output"
        return 1
    fi
}

# Validate WebLogic version in patch description
validate_weblogic_version() {
    local weblogic_patch=$1
    local expected_version=$2
    
    if [[ -z "$expected_version" ]]; then
        vlog "No WebLogic version provided, skipping version validation"
        return 0
    fi
    
    vlog "Validating WebLogic version: $expected_version"
    local patches_output=$(get_opatch_patches)
    
    if [[ -z "$patches_output" ]]; then
        log_error "Cannot retrieve patch list from OPatch"
        return 1
    fi
    
    # Find the WebLogic patch line
    local weblogic_line=$(echo "$patches_output" | grep -E "^${weblogic_patch}(;|$|[[:space:]])" | head -1)
    
    if [[ -z "$weblogic_line" ]]; then
        log_error "WebLogic patch $weblogic_patch not found for version validation"
        return 1
    fi
    
    # Check if version appears in the patch description
    if echo "$weblogic_line" | grep -q "$expected_version"; then
        log_info "Found WebLogic version in patch: $weblogic_line"
        log_success "WebLogic version validation PASSED"
        return 0
    else
        log_error "WebLogic version validation FAILED"
        log_error "Expected version: $expected_version"
        log_error "Patch line: $weblogic_line"
        return 1
    fi
}

# Validate WebLogic ID in lsinventory
validate_weblogic_id() {
    local weblogic_id=$1
    
    if [[ -z "$weblogic_id" ]]; then
        vlog "No WebLogic ID provided, skipping ID validation"
        return 0
    fi
    
    vlog "Validating WebLogic ID: $weblogic_id"
    local inventory_output=$(run_opatch_as_weblogic "lsinventory")
    
    # Check for errors
    if echo "$inventory_output" | grep -qi "The user is root\|cannot continue"; then
        log_error "Cannot retrieve inventory from OPatch"
        return 1
    fi
    
    # Search for the ID in inventory (may appear in comma-separated list)
    if echo "$inventory_output" | grep -q "$weblogic_id"; then
        local found_line=$(echo "$inventory_output" | grep "$weblogic_id" | head -1)
        log_info "Found WebLogic ID in inventory: $found_line"
        log_success "WebLogic ID validation PASSED"
        return 0
    else
        log_error "WebLogic ID validation FAILED"
        log_error "Expected ID: $weblogic_id"
        log_error "ID not found in lsinventory output"
        return 1
    fi
}

# ============================================================================
# WEBLOGIC VALIDATION AND INSTALLATION
# ============================================================================

# Validate WebLogic patches (ONLY patch ID and version)
validate_weblogic() {
    local weblogic_patch=$1
    local weblogic_version=$2
    
    log_info "Validating WebLogic patches..."
    echo
    
    if [[ -z "$weblogic_patch" ]]; then
        log_error "WebLogic patch number is required"
        return 1
    fi
    
    local all_passed=true
    
    # Validate WebLogic patch number from lspatches
    vlog "Step 1: Validating WebLogic patch number from lspatches..."
    if ! validate_patch_in_lspatches "$weblogic_patch" "weblogic"; then
        all_passed=false
    fi
    echo
    
    # Validate WebLogic version if provided
    if [[ -n "$weblogic_version" ]]; then
        vlog "Step 2: Validating WebLogic version from patch description..."
        if ! validate_weblogic_version "$weblogic_patch" "$weblogic_version"; then
            all_passed=false
        fi
        echo
    fi
    
    if [[ "$all_passed" == true ]]; then
        log_success "All WebLogic patches are up to date"
        return 0
    else
        log_warning "Some WebLogic patches are not up to date"
        return 1
    fi
}

# Install WebLogic patches
install_weblogic() {
    log_info "Installing WebLogic patches..."
    
    # Kill weblogic user processes
    vlog "Stopping WebLogic processes..."
    if killall -u "$WEBLOGIC_USER" 2>/dev/null; then
        log_success "WebLogic processes stopped"
    else
        log_warning "No WebLogic processes found or already stopped"
    fi
    
    # Remove puppet fact file
    vlog "Removing puppet fact file..."
    if [[ -f "$PUPPET_FACT_FILE" ]]; then
        rm -rf "$PUPPET_FACT_FILE"
        log_success "Puppet fact file removed"
    else
        log_warning "Puppet fact file not found (may already be removed)"
    fi
    
    # Run puppet agent
    log_info "Running puppet agent (this may take 10-30 minutes)..."
    log_warning "Puppet agent execution can take significant time..."
    
    if puppet agent -t; then
        log_success "Puppet agent completed successfully"
        return 0
    else
        log_error "Puppet agent execution failed"
        return 1
    fi
}

# Process WebLogic patches
process_weblogic() {
    log_info "=========================================="
    log_info "Processing WebLogic Patches"
    log_info "=========================================="
    echo
    
    local weblogic_patch="${WEBLOGIC_PATCH_NUMBER:-$DEFAULT_WEBLOGIC_PATCH}"
    local weblogic_version="${WEBLOGIC_VERSION:-$DEFAULT_WEBLOGIC_VERSION}"
    
    if [[ -z "$weblogic_patch" ]]; then
        log_error "WebLogic patch number is required. Please provide via -w flag or set DEFAULT_WEBLOGIC_PATCH"
        return 1
    fi
    
    vlog "WebLogic patch number: $weblogic_patch"
    [[ -n "$weblogic_version" ]] && vlog "WebLogic version: $weblogic_version"
    echo
    
    # Step 1: Validate current state
    vlog "Step 1: Validating current WebLogic patch state..."
    if validate_weblogic "$weblogic_patch" "$weblogic_version"; then
        log_success "WebLogic patches are already up to date. No installation needed."
        return 0
    fi
    
    log_warning "WebLogic validation failed. Proceeding with patch installation..."
    log_info "Note: WebLogic and Coherence patches are applied together via puppet agent."
    echo
    
    # Step 2: Install patches
    vlog "Step 2: Installing WebLogic patches..."
    if ! install_weblogic; then
        log_error "WebLogic patch installation failed"
        return 1
    fi
    echo
    
    # Step 3: Wait for services to stabilize
    vlog "Step 3: Waiting for services to stabilize..."
    sleep 5
    echo
    
    # Step 4: Re-validate
    vlog "Step 4: Re-validating WebLogic patches after installation..."
    if validate_weblogic "$weblogic_patch" "$weblogic_version"; then
        log_success "WebLogic patches are installed successfully!"
        return 0
    else
        log_error "WebLogic patch validation failed after installation"
        log_warning "Some patches may still need attention"
        return 1
    fi
}

# ============================================================================
# COHERENCE VALIDATION AND INSTALLATION
# ============================================================================

# Validate Coherence patches (patch ID and WebLogic ID from inventory)
validate_coherence() {
    local coherence_patch=$1
    local weblogic_id=$2
    
    log_info "Validating Coherence patches..."
    echo
    
    if [[ -z "$coherence_patch" ]]; then
        log_error "Coherence patch number is required"
        return 1
    fi
    
    local all_passed=true
    
    # Validate Coherence patch from lspatches
    vlog "Step 1: Validating Coherence patch number from lspatches..."
    if ! validate_patch_in_lspatches "$coherence_patch" "coherence"; then
        all_passed=false
    fi
    echo
    
    # Validate WebLogic ID from lsinventory (appears during Coherence validation)
    if [[ -n "$weblogic_id" ]]; then
        vlog "Step 2: Validating WebLogic ID from lsinventory (for Coherence)..."
        if ! validate_weblogic_id "$weblogic_id"; then
            all_passed=false
        fi
        echo
    fi
    
    if [[ "$all_passed" == true ]]; then
        log_success "All Coherence patches are up to date"
        return 0
    else
        log_warning "Some Coherence patches are not up to date"
        return 1
    fi
}

# Install Coherence patches (same as WebLogic - they're applied together)
install_coherence() {
    log_info "Installing Coherence patches..."
    
    # Kill weblogic user processes
    vlog "Stopping WebLogic processes..."
    if killall -u "$WEBLOGIC_USER" 2>/dev/null; then
        log_success "WebLogic processes stopped"
    else
        log_warning "No WebLogic processes found or already stopped"
    fi
    
    # Remove puppet fact file
    vlog "Removing puppet fact file..."
    if [[ -f "$PUPPET_FACT_FILE" ]]; then
        rm -rf "$PUPPET_FACT_FILE"
        log_success "Puppet fact file removed"
    else
        log_warning "Puppet fact file not found (may already be removed)"
    fi
    
    # Run puppet agent
    log_info "Running puppet agent (this may take 10-30 minutes)..."
    log_warning "Puppet agent execution can take significant time..."
    
    if puppet agent -t; then
        log_success "Puppet agent completed successfully"
        return 0
    else
        log_error "Puppet agent execution failed"
        return 1
    fi
}

# Process Coherence patches
process_coherence() {
    log_info "=========================================="
    log_info "Processing Coherence Patches"
    log_info "=========================================="
    echo
    
    local coherence_patch="${COHERENCE_PATCH_NUMBER:-$DEFAULT_COHERENCE_PATCH}"
    local weblogic_id="${WEBLOGIC_PATCH_ID:-$DEFAULT_WEBLOGIC_ID}"
    
    if [[ -z "$coherence_patch" ]]; then
        log_error "Coherence patch number is required. Please provide via -c flag or set DEFAULT_COHERENCE_PATCH"
        return 1
    fi
    
    vlog "Coherence patch number: $coherence_patch"
    [[ -n "$weblogic_id" ]] && vlog "WebLogic ID (for Coherence validation): $weblogic_id"
    echo
    
    # Step 1: Validate current state
    vlog "Step 1: Validating current Coherence patch state..."
    if validate_coherence "$coherence_patch" "$weblogic_id"; then
        log_success "Coherence patches are already up to date. No installation needed."
        return 0
    fi
    
    log_warning "Coherence validation failed. Proceeding with patch installation..."
    log_info "Note: WebLogic and Coherence patches are applied together via puppet agent."
    echo
    
    # Step 2: Install patches
    vlog "Step 2: Installing Coherence patches..."
    if ! install_coherence; then
        log_error "Coherence patch installation failed"
        return 1
    fi
    echo
    
    # Step 3: Wait for services to stabilize
    vlog "Step 3: Waiting for services to stabilize..."
    sleep 5
    echo
    
    # Step 4: Re-validate
    vlog "Step 4: Re-validating Coherence patches after installation..."
    if validate_coherence "$coherence_patch" "$weblogic_id"; then
        log_success "Coherence patches are installed successfully!"
        return 0
    else
        log_error "Coherence patch validation failed after installation"
        log_warning "Some patches may still need attention"
        return 1
    fi
}

# ============================================================================
# KERNEL VALIDATION AND INSTALLATION
# ============================================================================

# Get installed kernel version (from grubby)
get_installed_kernel() {
    if ! command_exists grubby; then
        return 1
    fi
    
    local grubby_output=$(grubby --default-kernel 2>/dev/null)
    
    if [[ -z "$grubby_output" ]]; then
        return 1
    fi
    
    # Extract kernel version
    local kernel_path=$(echo "$grubby_output" | grep -o '/boot/vmlinuz-[^[:space:]]*' | head -1)
    local kernel_version=""
    
    if [[ -n "$kernel_path" ]]; then
        kernel_version=$(echo "$kernel_path" | sed 's|/boot/vmlinuz-||')
    fi
    
    # Fallback: try to extract version pattern
    if [[ -z "$kernel_version" ]]; then
        kernel_version=$(echo "$grubby_output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[^[:space:]]*\.el[0-9_]+[^[:space:]]*' | head -1)
    fi
    
    if [[ -z "$kernel_version" ]]; then
        kernel_version=$(echo "$grubby_output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[^[:space:]]*' | head -1)
    fi
    
    echo "$kernel_version"
}

# Get current running kernel version (from uname)
get_current_kernel() {
    uname -r
}

# Validate kernel
validate_kernel() {
    local expected_kernel=$1
    
    log_info "Validating kernel patch..."
    
    if [[ -z "$expected_kernel" ]]; then
        log_error "Kernel version is required"
        return 1
    fi
    
    # Check if grubby exists
    if ! command_exists grubby; then
        log_error "grubby command not found. Please install grubby package."
        return 1
    fi
    
    # Get installed kernel (from grubby)
    local installed_kernel=$(get_installed_kernel)
    if [[ -z "$installed_kernel" ]]; then
        log_error "Cannot determine installed kernel from grubby"
        return 1
    fi
    
    # Get current running kernel (from uname)
    local current_kernel=$(get_current_kernel)
    if [[ -z "$current_kernel" ]]; then
        log_error "Cannot determine current kernel from uname"
        return 1
    fi
    
    log_info "Installed kernel (from grubby): $installed_kernel"
    log_info "Current running kernel (from uname -r): $current_kernel"
    log_info "Expected kernel version: $expected_kernel"
    echo
    
    # Check if installed kernel matches expected
    if [[ "$installed_kernel" == *"$expected_kernel"* ]]; then
        # Check if current kernel also matches (patch is applied)
        if [[ "$current_kernel" == *"$expected_kernel"* ]]; then
            log_success "RHEL kernel patch is up to date and applied"
            return 0
        else
            log_warning "RHEL kernel patch is installed but not applied"
            log_info "Installed kernel: $installed_kernel"
            log_info "Current kernel: $current_kernel"
            log_warning "Please reboot the server to apply the patch"
            return 2  # Special return code for "installed but not applied"
        fi
    else
        log_warning "RHEL kernel patch is not installed"
        log_error "Installed kernel: $installed_kernel"
        log_error "Expected kernel: $expected_kernel"
        return 1
    fi
}

# Install kernel patches
install_kernel() {
    log_info "Installing kernel patches..."
    
    # Check if install script exists
    if [[ ! -f "$KERNEL_INSTALL_SCRIPT" ]]; then
        log_error "Kernel installation script not found: $KERNEL_INSTALL_SCRIPT"
        return 1
    fi
    
    # Change to install directory
    if [[ ! -d "$KERNEL_INSTALL_DIR" ]]; then
        log_error "Kernel install directory not found: $KERNEL_INSTALL_DIR"
        return 1
    fi
    
    cd "$KERNEL_INSTALL_DIR" || {
        log_error "Cannot change to directory: $KERNEL_INSTALL_DIR"
        return 1
    }
    
    # Execute patch installation command
    local cmd="./$(basename "$KERNEL_INSTALL_SCRIPT") -r rhel8-updates-repo,rhel-appstream,rsyslog -a n -e rsyslog\*,puppet-agent,savinstpkg,COMMVAULT-FILESYSTEM-USHOSTING.Instance001,COMMVAULT-FILESYSTEM-GB00-UKFML.Instance001,COMMVAULT-FILESYSTEM-GB03-UKCOLT.Instance001,COMMVAULT-FILESYSTEM-CH01.Instance001 -s n -g y"
    
    vlog "Executing: $cmd"
    log_warning "This may take several minutes..."
    
    if eval "$cmd"; then
        log_success "Kernel patch installation completed"
        return 0
    else
        log_error "Kernel patch installation failed"
        return 1
    fi
}

# Process kernel patches
process_kernel() {
    log_info "=========================================="
    log_info "Processing RHEL Kernel Patches"
    log_info "=========================================="
    echo
    
    local expected_kernel="${KERNEL_VERSION:-$DEFAULT_KERNEL_VERSION}"
    
    if [[ -z "$expected_kernel" ]]; then
        log_error "Kernel version is required. Please provide via -r flag or set DEFAULT_KERNEL_VERSION"
        return 1
    fi
    
    vlog "Expected kernel version: $expected_kernel"
    echo
    
    # Step 1: Validate current state
    vlog "Step 1: Validating current kernel state..."
    local validation_result
    validate_kernel "$expected_kernel"
    validation_result=$?
    
    if [[ $validation_result -eq 0 ]]; then
        log_success "RHEL kernel patch is up to date. No installation needed."
        return 0
    elif [[ $validation_result -eq 2 ]]; then
        log_info "RHEL kernel patch is installed but not applied."
        log_warning "Please reboot the server to apply the patch."
        return 0  # This is actually success - patch is installed, just needs reboot
    fi
    
    log_warning "Kernel validation failed. Proceeding with patch installation..."
    echo
    
    # Step 2: Install patches
    vlog "Step 2: Installing kernel patches..."
    if ! install_kernel; then
        log_error "Kernel patch installation failed"
        return 1
    fi
    echo
    
    # Step 3: Verify installation
    vlog "Step 3: Verifying kernel patch installation..."
    validate_kernel "$expected_kernel"
    validation_result=$?
    
    if [[ $validation_result -eq 0 ]]; then
        log_success "RHEL kernel patch is installed and applied successfully!"
        return 0
    elif [[ $validation_result -eq 2 ]]; then
        log_success "RHEL kernel patch is installed successfully!"
        log_info "Installed kernel: $(get_installed_kernel)"
        log_info "Current kernel: $(get_current_kernel)"
        log_warning "Please reboot the server to apply the patch."
        return 0
    else
        log_error "Kernel patch verification failed after installation"
        log_error "Patch installation may have failed"
        return 1
    fi
}

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

parse_arguments() {
    local args=("$@")
    local i=0
    
    while [[ $i -lt ${#args[@]} ]]; do
        local arg="${args[$i]}"
        local normalized=$(normalize_flag "$arg")
        
        case "$normalized" in
            -w|--weblogic)
                PROCESS_WEBLOGIC=true
                # Check for WebLogic patch number
                if [[ $((i+1)) -lt ${#args[@]} ]] && [[ "${args[$((i+1))]}" =~ ^[0-9]+$ ]]; then
                    WEBLOGIC_PATCH_NUMBER="${args[$((i+1))]}"
                    ((i++))
                    # Check for WebLogic version (contains dots)
                    if [[ $((i+1)) -lt ${#args[@]} ]] && [[ "${args[$((i+1))]}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
                        WEBLOGIC_VERSION="${args[$((i+1))]}"
                        ((i++))
                    fi
                fi
                ;;
            -c|--coherence)
                PROCESS_COHERENCE=true
                # Check for Coherence patch number
                if [[ $((i+1)) -lt ${#args[@]} ]] && [[ "${args[$((i+1))]}" =~ ^[0-9]+$ ]]; then
                    COHERENCE_PATCH_NUMBER="${args[$((i+1))]}"
                    ((i++))
                    # Check for WebLogic ID (appears during Coherence validation)
                    if [[ $((i+1)) -lt ${#args[@]} ]] && [[ "${args[$((i+1))]}" =~ ^[0-9]+$ ]]; then
                        WEBLOGIC_PATCH_ID="${args[$((i+1))]}"
                        ((i++))
                    fi
                fi
                ;;
            -r|--rhel|-o|--kernel)
                PROCESS_KERNEL=true
                # Check if next argument looks like a kernel version
                if [[ $((i+1)) -lt ${#args[@]} ]] && [[ "${args[$((i+1))]}" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
                    KERNEL_VERSION="${args[$((i+1))]}"
                    ((i++))
                fi
                ;;
            -v|--verbose)
                VERBOSE=true
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $arg"
                log_info "Use -h or --help for usage information"
                exit 1
                ;;
        esac
        ((i++))
    done
    
    # If no patches selected, show usage
    if [[ "$PROCESS_WEBLOGIC" == false ]] && [[ "$PROCESS_COHERENCE" == false ]] && [[ "$PROCESS_KERNEL" == false ]]; then
        log_error "No patches selected. Please specify at least one patch type."
        echo
        show_usage
        exit 1
    fi
}

# ============================================================================
# MAIN FUNCTION
# ============================================================================

main() {
    # Check root privileges
    check_root
    
    # Parse arguments
    parse_arguments "$@"
    
    # Display header
    display_header
    
    if [[ "$VERBOSE" == true ]]; then
        log_info "Verbose mode enabled"
        log_info "Selected patches:"
        [[ "$PROCESS_WEBLOGIC" == true ]] && log_info "  - WebLogic"
        [[ "$PROCESS_COHERENCE" == true ]] && log_info "  - Coherence"
        [[ "$PROCESS_KERNEL" == true ]] && log_info "  - RHEL/Kernel"
        echo
    fi
    
    local overall_success=true
    
    # Process WebLogic patches
    if [[ "$PROCESS_WEBLOGIC" == true ]]; then
        if ! process_weblogic; then
            overall_success=false
        fi
        echo
    fi
    
    # Process Coherence patches
    if [[ "$PROCESS_COHERENCE" == true ]]; then
        if ! process_coherence; then
            overall_success=false
        fi
        echo
    fi
    
    # Process Kernel patches
    if [[ "$PROCESS_KERNEL" == true ]]; then
        if ! process_kernel; then
            overall_success=false
        fi
        echo
    fi
    
    # Final summary
    log_info "=========================================="
    log_info "Automated Patching Summary"
    log_info "=========================================="
    if [[ "$overall_success" == true ]]; then
        log_success "All selected patches processed successfully!"
    else
        log_error "Some patches failed. Please review the output above."
        exit 1
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
