#!/bin/bash
#
# liberate.sh - Convert Enterprise Linux to SUSE Liberty Linux / SLES Expanded Support
#
# This script automates the conversion of Enterprise Linux distributions
# (Rocky, AlmaLinux, Oracle Linux, CentOS, RHEL, EuroLinux) to SUSE Liberty Linux
# or SLES Expanded Support.
#
# Based on the liberate-formula Salt formula, with extended features:
# - Automatic backup before migration
# - Rollback capability
# - Extended distribution support
# - Interactive mode
# - Detailed migration reports
#
# Usage: liberate.sh [OPTIONS]
#
# Copyright (c) 2024 - Released under MIT License
#

set -euo pipefail

# =============================================================================
# Configuration Variables
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="1.2.0"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Paths
readonly LIBERATED_MARKER="/etc/sysconfig/liberated"
readonly DEFAULT_BACKUP_DIR="/var/lib/liberate/backups"
readonly LOG_FILE="/var/log/liberate.log"
readonly DNF_MIGRATION_LOG="/var/log/dnf_sll_migration.log"
readonly YUM_MIGRATION_LOG="/var/log/yum_sles_es_migration.log"

# Options (defaults)
REINSTALL_PACKAGES=false
INSTALL_LOGOS=false
DRY_RUN=false
NO_BACKUP=false
BACKUP_DIR="$DEFAULT_BACKUP_DIR"
DO_ROLLBACK=false
DO_RESTORE=false
DO_RESTORE_MINIMAL=false
RESTORE_BACKUP=""
INTERACTIVE=false
FORCE=false
GENERATE_REPORT=false
VERBOSE=false
LIST_BACKUPS=false
EXPORT_BACKUP=""
IMPORT_BACKUP=""

# Runtime variables
OS_NAME=""
OS_VERSION=""
OS_VERSION_MAJOR=""
OS_ID=""
BACKUP_TIMESTAMP=""
CURRENT_BACKUP_DIR=""
ORIGINAL_RELEASE_PKGS=()
ORIGINAL_RELEASE_RPMS_DIR=""

# =============================================================================
# Utility Functions
# =============================================================================

# Print colored message
print_color() {
    local color="$1"
    local message="$2"
    local nc='\033[0m'

    case "$color" in
        red)    echo -e "\033[0;31m${message}${nc}" ;;
        green)  echo -e "\033[0;32m${message}${nc}" ;;
        yellow) echo -e "\033[0;33m${message}${nc}" ;;
        blue)   echo -e "\033[0;34m${message}${nc}" ;;
        *)      echo "$message" ;;
    esac
}

# Log message to file and optionally to stdout
log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"

    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"

    case "$level" in
        ERROR)
            print_color red "ERROR: $message" >&2
            ;;
        WARN)
            print_color yellow "WARNING: $message"
            ;;
        INFO)
            if [[ "$VERBOSE" == true ]]; then
                print_color blue "INFO: $message"
            fi
            ;;
        SUCCESS)
            print_color green "$message"
            ;;
        *)
            if [[ "$VERBOSE" == true ]]; then
                echo "$message"
            fi
            ;;
    esac
}

# Execute command or show in dry-run mode
run_cmd() {
    local cmd="$*"

    if [[ "$DRY_RUN" == true ]]; then
        print_color yellow "[DRY-RUN] $cmd"
        log_message "DRY-RUN" "$cmd"
        return 0
    fi

    log_message "INFO" "Executing: $cmd"

    if [[ "$VERBOSE" == true ]]; then
        eval "$cmd"
    else
        eval "$cmd" 2>&1 | while IFS= read -r line; do
            log_message "DEBUG" "$line"
        done
    fi

    return "${PIPESTATUS[0]}"
}

# Ask for confirmation in interactive mode
confirm() {
    local prompt="$1"
    local default="${2:-n}"

    if [[ "$INTERACTIVE" != true ]]; then
        return 0
    fi

    local yn_prompt
    if [[ "$default" == "y" ]]; then
        yn_prompt="[Y/n]"
    else
        yn_prompt="[y/N]"
    fi

    while true; do
        read -r -p "$prompt $yn_prompt: " response
        response="${response:-$default}"
        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "This script must be run as root"
        exit 1
    fi
}

# =============================================================================
# Detection Functions
# =============================================================================

# Detect the operating system
detect_os() {
    log_message "INFO" "Detecting operating system..."

    if [[ ! -f /etc/os-release ]]; then
        log_message "ERROR" "Cannot detect OS: /etc/os-release not found"
        exit 1
    fi

    # Source os-release for ID and VERSION_ID
    # shellcheck source=/dev/null
    source /etc/os-release

    OS_ID="${ID:-unknown}"

    case "$OS_ID" in
        rocky)
            OS_NAME="Rocky Linux"
            ;;
        almalinux)
            OS_NAME="AlmaLinux"
            ;;
        ol|oracle)
            OS_NAME="Oracle Linux"
            ;;
        centos)
            if [[ -f /etc/centos-release ]] && grep -qi "stream" /etc/centos-release 2>/dev/null; then
                OS_NAME="CentOS Stream"
            else
                OS_NAME="CentOS"
            fi
            ;;
        rhel)
            OS_NAME="Red Hat Enterprise Linux"
            ;;
        eurolinux)
            OS_NAME="EuroLinux"
            ;;
        sles|suse|sll)
            OS_NAME="SUSE"
            ;;
        *)
            log_message "ERROR" "Unsupported distribution: $os_id"
            exit 1
            ;;
    esac

    log_message "INFO" "Detected OS: $OS_NAME"
}

# Detect the OS version
detect_version() {
    log_message "INFO" "Detecting OS version..."

    # shellcheck source=/dev/null
    source /etc/os-release

    OS_VERSION="${VERSION_ID:-unknown}"
    OS_VERSION_MAJOR="${OS_VERSION%%.*}"

    case "$OS_VERSION_MAJOR" in
        7|8|9)
            log_message "INFO" "Detected version: $OS_VERSION (major: $OS_VERSION_MAJOR)"
            ;;
        *)
            log_message "ERROR" "Unsupported version: $OS_VERSION (major version $OS_VERSION_MAJOR)"
            exit 1
            ;;
    esac
}

# Check if system is already liberated
check_already_liberated() {
    log_message "INFO" "Checking if system is already liberated..."

    if [[ -f "$LIBERATED_MARKER" ]]; then
        # shellcheck source=/dev/null
        source "$LIBERATED_MARKER"

        if [[ "${LIBERATED:-false}" == "true" ]]; then
            if [[ "$FORCE" != true ]]; then
                log_message "WARN" "System already liberated on ${LIBERATED_DATE:-unknown}"
                log_message "WARN" "Original OS: ${LIBERATED_FROM:-unknown}"
                log_message "WARN" "Use --force to re-run migration"
                exit 0
            else
                log_message "WARN" "System already liberated, but --force specified. Continuing..."
            fi
        fi
    fi
}

# =============================================================================
# Prerequisites Check Functions
# =============================================================================

# Check all prerequisites before migration
check_prerequisites() {
    log_message "INFO" "Checking prerequisites..."

    local errors=0

    # Check disk space
    check_disk_space || ((errors++))

    # Check network connectivity to repos (basic check)
    check_repo_connectivity || ((errors++))

    # Check required commands
    check_required_commands || ((errors++))

    if [[ $errors -gt 0 ]]; then
        log_message "ERROR" "Prerequisites check failed with $errors error(s)"
        exit 1
    fi

    log_message "SUCCESS" "All prerequisites satisfied"
}

# Check available disk space
check_disk_space() {
    local min_space_mb=100
    local available_mb

    available_mb=$(df -m /var 2>/dev/null | awk 'NR==2 {print $4}')

    if [[ -z "$available_mb" ]]; then
        log_message "WARN" "Could not determine available disk space"
        return 0
    fi

    if [[ "$available_mb" -lt "$min_space_mb" ]]; then
        log_message "ERROR" "Insufficient disk space: ${available_mb}MB available, ${min_space_mb}MB required"
        return 1
    fi

    log_message "INFO" "Disk space check passed: ${available_mb}MB available"
    return 0
}

# Check repository connectivity
check_repo_connectivity() {
    log_message "INFO" "Checking repository connectivity..."

    # Just check if we can reach the package manager
    if command -v dnf &>/dev/null; then
        if ! dnf repolist &>/dev/null; then
            log_message "WARN" "DNF repository check failed - ensure SUSE repos are configured"
        fi
    elif command -v yum &>/dev/null; then
        if ! yum repolist &>/dev/null; then
            log_message "WARN" "YUM repository check failed - ensure SUSE repos are configured"
        fi
    fi

    return 0
}

# Check required commands are available
check_required_commands() {
    local required_cmds=("rpm" "cat" "mkdir" "cp" "date")
    local missing=()

    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    # Check for dnf or yum
    if ! command -v dnf &>/dev/null && ! command -v yum &>/dev/null; then
        missing+=("dnf or yum")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_message "ERROR" "Missing required commands: ${missing[*]}"
        return 1
    fi

    return 0
}

# =============================================================================
# Backup Functions
# =============================================================================

# Create backup before migration
create_backup() {
    if [[ "$NO_BACKUP" == true ]]; then
        log_message "INFO" "Backup disabled by --no-backup option"
        return 0
    fi

    log_message "INFO" "Creating backup..."

    BACKUP_TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
    CURRENT_BACKUP_DIR="${BACKUP_DIR}/${BACKUP_TIMESTAMP}"

    if [[ "$DRY_RUN" == true ]]; then
        log_message "DRY-RUN" "Would create backup at $CURRENT_BACKUP_DIR"
        return 0
    fi

    # Create backup directory structure
    mkdir -p "$CURRENT_BACKUP_DIR"/{repos,release-files,dnf-yum-config}

    # Backup installed packages list
    log_message "INFO" "Backing up package list..."
    rpm -qa --queryformat '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > "$CURRENT_BACKUP_DIR/packages.list"

    # Backup repository files
    log_message "INFO" "Backing up repository configuration..."
    if [[ -d /etc/yum.repos.d ]]; then
        cp -a /etc/yum.repos.d/* "$CURRENT_BACKUP_DIR/repos/" 2>/dev/null || true
    fi

    # Backup release files
    log_message "INFO" "Backing up release files..."
    for file in /etc/os-release /etc/redhat-release /etc/system-release /etc/centos-release; do
        if [[ -f "$file" ]]; then
            cp -a "$file" "$CURRENT_BACKUP_DIR/release-files/" 2>/dev/null || true
        fi
    done

    # Backup dnf/yum configuration
    log_message "INFO" "Backing up package manager configuration..."
    [[ -f /etc/dnf/dnf.conf ]] && cp -a /etc/dnf/dnf.conf "$CURRENT_BACKUP_DIR/dnf-yum-config/"
    [[ -f /etc/yum.conf ]] && cp -a /etc/yum.conf "$CURRENT_BACKUP_DIR/dnf-yum-config/"
    [[ -d /etc/dnf/protected.d ]] && cp -a /etc/dnf/protected.d "$CURRENT_BACKUP_DIR/dnf-yum-config/" 2>/dev/null || true

    # Backup release RPM files
    backup_release_rpms "$CURRENT_BACKUP_DIR"

    # Backup files that will be deleted
    backup_deleted_files "$CURRENT_BACKUP_DIR"

    # Create metadata file
    log_message "INFO" "Creating backup metadata..."
    local rpm_count
    rpm_count=$(find "$CURRENT_BACKUP_DIR/rpms" -name "*.rpm" -type f 2>/dev/null | wc -l)

    cat > "$CURRENT_BACKUP_DIR/metadata.json" << EOF
{
    "backup_date": "$(date '+%Y-%m-%d %H:%M:%S')",
    "backup_timestamp": "$BACKUP_TIMESTAMP",
    "os_name": "$OS_NAME",
    "os_id": "$OS_ID",
    "os_version": "$OS_VERSION",
    "os_version_major": "$OS_VERSION_MAJOR",
    "hostname": "$(hostname)",
    "kernel": "$(uname -r)",
    "package_count": $(rpm -qa | wc -l),
    "release_rpm_count": $rpm_count,
    "script_version": "$SCRIPT_VERSION"
}
EOF

    # Create a symlink to latest backup
    ln -sfn "$CURRENT_BACKUP_DIR" "${BACKUP_DIR}/latest"

    log_message "SUCCESS" "Backup created at $CURRENT_BACKUP_DIR"

    # Show backup summary
    echo ""
    echo "Backup summary:"
    echo "  Location: $CURRENT_BACKUP_DIR"
    echo "  Release RPMs: $rpm_count"
    echo "  Total packages: $(wc -l < "$CURRENT_BACKUP_DIR/packages.list")"
    echo ""
}

# Rollback to previous state
rollback() {
    log_message "INFO" "Starting rollback process..."

    # Find the latest backup
    local latest_backup="${BACKUP_DIR}/latest"

    if [[ ! -L "$latest_backup" ]] || [[ ! -d "$latest_backup" ]]; then
        log_message "ERROR" "No backup found to restore from"
        exit 1
    fi

    local backup_path
    backup_path="$(readlink -f "$latest_backup")"

    log_message "INFO" "Restoring from backup: $backup_path"

    if [[ ! -f "$backup_path/metadata.json" ]]; then
        log_message "ERROR" "Invalid backup: metadata.json not found"
        exit 1
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_message "DRY-RUN" "Would restore from $backup_path"
        return 0
    fi

    # Restore repository files
    if [[ -d "$backup_path/repos" ]] && [[ -n "$(ls -A "$backup_path/repos" 2>/dev/null)" ]]; then
        log_message "INFO" "Restoring repository configuration..."
        cp -a "$backup_path/repos/"* /etc/yum.repos.d/
    fi

    # Restore dnf protected.d if it existed
    if [[ -d "$backup_path/dnf-yum-config/protected.d" ]]; then
        log_message "INFO" "Restoring DNF protected.d..."
        mkdir -p /etc/dnf/protected.d
        cp -a "$backup_path/dnf-yum-config/protected.d/"* /etc/dnf/protected.d/
    fi

    # Note: We cannot fully restore release packages without reinstalling from original repos
    log_message "WARN" "Repository files restored. To complete rollback:"
    log_message "WARN" "1. Ensure original distribution repos are configured"
    log_message "WARN" "2. Remove SUSE release packages manually"
    log_message "WARN" "3. Install original release packages"
    log_message "WARN" "Package list available at: $backup_path/packages.list"

    # Remove liberated marker
    if [[ -f "$LIBERATED_MARKER" ]]; then
        rm -f "$LIBERATED_MARKER"
        log_message "INFO" "Removed liberated marker"
    fi

    log_message "SUCCESS" "Partial rollback completed. Manual steps may be required."
}

# Cleanup old backups
cleanup_backup() {
    local keep_count="${1:-5}"

    if [[ ! -d "$BACKUP_DIR" ]]; then
        return 0
    fi

    log_message "INFO" "Cleaning up old backups (keeping last $keep_count)..."

    local backup_count
    backup_count=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "[0-9]*_[0-9]*" 2>/dev/null | wc -l)

    if [[ "$backup_count" -le "$keep_count" ]]; then
        log_message "INFO" "No cleanup needed ($backup_count backups exist)"
        return 0
    fi

    # Remove oldest backups
    find "$BACKUP_DIR" -maxdepth 1 -type d -name "[0-9]*_[0-9]*" -printf '%T+ %p\n' | \
        sort | head -n -"$keep_count" | cut -d' ' -f2- | while read -r dir; do
        if [[ "$DRY_RUN" == true ]]; then
            log_message "DRY-RUN" "Would remove old backup: $dir"
        else
            log_message "INFO" "Removing old backup: $dir"
            rm -rf "$dir"
        fi
    done
}

# =============================================================================
# Release Package Detection and RPM Backup Functions
# =============================================================================

# Get list of release-related packages for the current distribution
get_release_packages() {
    local os_id="$1"
    local version_major="$2"
    local packages=()

    case "$os_id" in
        rocky)
            packages+=("rocky-release" "rocky-repos" "rocky-gpg-keys")
            if [[ "$version_major" == "9" ]]; then
                packages+=("rocky-release-9")
            elif [[ "$version_major" == "8" ]]; then
                packages+=("rocky-release-8")
            fi
            ;;
        almalinux)
            packages+=("almalinux-release" "almalinux-repos" "almalinux-gpg-keys")
            ;;
        ol|oracle)
            packages+=("oraclelinux-release" "oraclelinux-release-el${version_major}")
            packages+=("oracle-epel-release-el${version_major}" "oracle-release-el${version_major}")
            ;;
        centos)
            if [[ "$version_major" == "7" ]]; then
                packages+=("centos-release" "centos-release-cr")
            else
                packages+=("centos-stream-release" "centos-stream-repos" "centos-gpg-keys")
            fi
            ;;
        rhel)
            packages+=("redhat-release" "redhat-release-server")
            ;;
        eurolinux)
            packages+=("eurolinux-release" "eurolinux-repos")
            ;;
    esac

    # Add common packages that might exist
    packages+=("system-release" "redhat-logos" "os-prober")

    # Filter to only installed packages
    local installed=()
    for pkg in "${packages[@]}"; do
        if rpm -q "$pkg" &>/dev/null; then
            installed+=("$pkg")
        fi
    done

    # Also find any other *-release packages
    while IFS= read -r pkg; do
        local found=false
        for existing in "${installed[@]}"; do
            if [[ "$pkg" == "$existing" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == false ]]; then
            installed+=("$pkg")
        fi
    done < <(rpm -qa --queryformat '%{NAME}\n' | grep -E '^[a-z]+-release(-[a-z0-9]+)?$' | grep -v sll | grep -v sles)

    echo "${installed[@]}"
}

# Backup release RPM files from the system
backup_release_rpms() {
    local backup_dir="$1"
    local rpm_dir="${backup_dir}/rpms"

    log_message "INFO" "Backing up release RPM files..."

    if [[ "$DRY_RUN" == true ]]; then
        log_message "DRY-RUN" "Would backup release RPMs to $rpm_dir"
        return 0
    fi

    mkdir -p "$rpm_dir"

    # Get list of release packages
    local release_pkgs
    release_pkgs=$(get_release_packages "$OS_ID" "$OS_VERSION_MAJOR")

    if [[ -z "$release_pkgs" ]]; then
        log_message "WARN" "No release packages found to backup"
        return 0
    fi

    log_message "INFO" "Release packages to backup: $release_pkgs"

    # Save the package list
    echo "$release_pkgs" | tr ' ' '\n' > "${backup_dir}/release-packages.list"

    # Try to download the RPMs using different methods
    local download_success=false

    # Method 1: Use dnf/yum download if available
    if command -v dnf &>/dev/null; then
        log_message "INFO" "Using dnf to download RPMs..."
        if dnf download --destdir="$rpm_dir" $release_pkgs 2>/dev/null; then
            download_success=true
        fi
    elif command -v yumdownloader &>/dev/null; then
        log_message "INFO" "Using yumdownloader to download RPMs..."
        if yumdownloader --destdir="$rpm_dir" $release_pkgs 2>/dev/null; then
            download_success=true
        fi
    elif command -v yum &>/dev/null; then
        log_message "INFO" "Using yum to download RPMs..."
        # yum doesn't have download subcommand in older versions
        if yum install --downloadonly --downloaddir="$rpm_dir" $release_pkgs -y 2>/dev/null; then
            download_success=true
        fi
    fi

    # Method 2: If download failed, try to copy from RPM database cache
    if [[ "$download_success" == false ]]; then
        log_message "INFO" "Direct download failed, attempting to extract from RPM database..."

        for pkg in $release_pkgs; do
            local pkg_file
            pkg_file=$(rpm -q --queryformat '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}.rpm\n' "$pkg" 2>/dev/null)

            # Check common RPM cache locations
            for cache_dir in /var/cache/yum /var/cache/dnf /var/lib/rpm; do
                if find "$cache_dir" -name "$pkg_file" -type f 2>/dev/null | head -1 | grep -q .; then
                    local found_rpm
                    found_rpm=$(find "$cache_dir" -name "$pkg_file" -type f 2>/dev/null | head -1)
                    cp "$found_rpm" "$rpm_dir/" 2>/dev/null && download_success=true
                    break
                fi
            done
        done
    fi

    # Method 3: Use repoquery to find URLs and download
    if [[ "$download_success" == false ]] && command -v repoquery &>/dev/null; then
        log_message "INFO" "Trying repoquery method..."
        for pkg in $release_pkgs; do
            local url
            url=$(repoquery --location "$pkg" 2>/dev/null | head -1)
            if [[ -n "$url" ]] && curl -sL -o "${rpm_dir}/${pkg}.rpm" "$url" 2>/dev/null; then
                download_success=true
            fi
        done
    fi

    # Count downloaded RPMs
    local rpm_count
    rpm_count=$(find "$rpm_dir" -name "*.rpm" -type f 2>/dev/null | wc -l)

    if [[ "$rpm_count" -gt 0 ]]; then
        log_message "SUCCESS" "Backed up $rpm_count RPM file(s) to $rpm_dir"

        # Create checksums
        (cd "$rpm_dir" && sha256sum *.rpm > SHA256SUMS 2>/dev/null) || true
    else
        log_message "WARN" "Could not download release RPMs. Backup will contain package list only."
        log_message "WARN" "For full restore capability, manually copy RPMs to: $rpm_dir"
    fi

    # Save additional package info for manual restore
    log_message "INFO" "Saving detailed package information..."
    for pkg in $release_pkgs; do
        rpm -qi "$pkg" >> "${backup_dir}/release-packages-info.txt" 2>/dev/null || true
        echo "---" >> "${backup_dir}/release-packages-info.txt"
    done
}

# Backup files and directories that will be deleted during liberation
backup_deleted_files() {
    local backup_dir="$1"
    local deleted_dir="${backup_dir}/deleted-files"

    log_message "INFO" "Backing up files that will be deleted..."

    if [[ "$DRY_RUN" == true ]]; then
        log_message "DRY-RUN" "Would backup deleted files to $deleted_dir"
        return 0
    fi

    mkdir -p "$deleted_dir"

    # List of files/directories that are deleted during liberation
    local files_to_backup=(
        "/usr/share/redhat-release"
        "/etc/dnf/protected.d/redhat-release.conf"
        "/etc/os-release"
        "/etc/redhat-release"
        "/etc/system-release"
        "/etc/system-release-cpe"
        "/etc/centos-release"
        "/etc/oracle-release"
        "/etc/rocky-release"
        "/etc/almalinux-release"
        "/etc/eurolinux-release"
    )

    local backed_up=0

    for item in "${files_to_backup[@]}"; do
        if [[ -e "$item" ]]; then
            # Create parent directory structure
            local parent_dir
            parent_dir=$(dirname "$item")
            mkdir -p "${deleted_dir}${parent_dir}"

            if [[ -d "$item" ]]; then
                # Copy directory recursively
                cp -a "$item" "${deleted_dir}${parent_dir}/" 2>/dev/null && ((backed_up++))
                log_message "INFO" "Backed up directory: $item"
            else
                # Copy file
                cp -a "$item" "${deleted_dir}${item}" 2>/dev/null && ((backed_up++))
                log_message "INFO" "Backed up file: $item"
            fi
        fi
    done

    # Create manifest of backed up files
    find "$deleted_dir" -type f -o -type l 2>/dev/null | sed "s|${deleted_dir}||" > "${backup_dir}/deleted-files.manifest"

    log_message "SUCCESS" "Backed up $backed_up file(s)/directory(ies) that will be deleted"
}

# Minimal restore - only restore deleted files and release package
restore_minimal() {
    local backup_name="${RESTORE_BACKUP:-latest}"
    local backup_path

    log_message "INFO" "Starting minimal restore (deleted files and release package only)..."

    # Resolve backup path
    if [[ "$backup_name" == "latest" ]]; then
        if [[ ! -L "${BACKUP_DIR}/latest" ]]; then
            log_message "ERROR" "No latest backup found"
            list_backups
            exit 1
        fi
        backup_path=$(readlink -f "${BACKUP_DIR}/latest")
    else
        backup_path="${BACKUP_DIR}/${backup_name}"
    fi

    if [[ ! -d "$backup_path" ]]; then
        log_message "ERROR" "Backup not found: $backup_path"
        list_backups
        exit 1
    fi

    log_message "INFO" "Restoring from backup: $backup_path"

    # Load original OS info from metadata
    local orig_os_name orig_os_version
    if command -v jq &>/dev/null; then
        orig_os_name=$(jq -r '.os_name' "$backup_path/metadata.json")
        orig_os_version=$(jq -r '.os_version' "$backup_path/metadata.json")
    else
        orig_os_name=$(grep -o '"os_name"[^,]*' "$backup_path/metadata.json" | cut -d'"' -f4)
        orig_os_version=$(grep -o '"os_version"[^,]*' "$backup_path/metadata.json" | cut -d'"' -f4)
    fi

    echo ""
    print_color blue "Minimal Restore Information:"
    echo "  Backup: $(basename "$backup_path")"
    echo "  Original OS: $orig_os_name $orig_os_version"
    echo ""
    echo "This will restore:"
    echo "  - Deleted files (/usr/share/redhat-release, /etc/dnf/protected.d/*, etc.)"
    echo "  - Original release package(s)"
    echo ""
    echo "This will NOT remove SUSE packages (use --restore for full restore)"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        log_message "DRY-RUN" "Would perform minimal restore"
        return 0
    fi

    if ! confirm "Proceed with minimal restore?"; then
        log_message "INFO" "Restore cancelled by user"
        exit 0
    fi

    local restored_count=0

    # Step 1: Restore deleted files
    log_message "INFO" "Step 1/2: Restoring deleted files..."

    local deleted_dir="${backup_path}/deleted-files"
    if [[ -d "$deleted_dir" ]]; then
        # Restore each file/directory from the backup
        if [[ -f "${backup_path}/deleted-files.manifest" ]]; then
            while IFS= read -r file; do
                if [[ -n "$file" ]] && [[ -e "${deleted_dir}${file}" ]]; then
                    local parent_dir
                    parent_dir=$(dirname "$file")
                    mkdir -p "$parent_dir" 2>/dev/null || true

                    if cp -a "${deleted_dir}${file}" "$file" 2>/dev/null; then
                        log_message "INFO" "Restored: $file"
                        ((restored_count++))
                    else
                        log_message "WARN" "Failed to restore: $file"
                    fi
                fi
            done < "${backup_path}/deleted-files.manifest"
        else
            # Fallback: copy everything from deleted-files
            cp -a "${deleted_dir}/"* / 2>/dev/null || true
            log_message "INFO" "Restored deleted files from backup"
        fi
    else
        log_message "WARN" "No deleted-files directory in backup"
    fi

    # Step 2: Install original release package
    log_message "INFO" "Step 2/2: Installing original release package..."

    local rpm_dir="${backup_path}/rpms"
    local rpms_installed=false

    if [[ -d "$rpm_dir" ]] && [[ -n "$(ls -A "$rpm_dir"/*.rpm 2>/dev/null)" ]]; then
        log_message "INFO" "Installing RPMs from backup..."

        # Install the RPMs (force to handle conflicts with SUSE packages)
        if rpm -Uvh --force --nodeps "$rpm_dir"/*.rpm 2>&1 | tee -a "$LOG_FILE"; then
            rpms_installed=true
            log_message "SUCCESS" "Release packages installed from backup"
        else
            log_message "WARN" "Some RPMs failed to install"
        fi
    else
        # Try to install from repos using package list
        if [[ -f "$backup_path/release-packages.list" ]]; then
            log_message "INFO" "RPMs not in backup, attempting install from repositories..."
            local pkg_list
            pkg_list=$(cat "$backup_path/release-packages.list" | tr '\n' ' ')

            if command -v dnf &>/dev/null; then
                dnf install -y --allowerasing $pkg_list 2>&1 | tee -a "$LOG_FILE" && rpms_installed=true
            elif command -v yum &>/dev/null; then
                yum install -y $pkg_list 2>&1 | tee -a "$LOG_FILE" && rpms_installed=true
            fi
        fi
    fi

    if [[ "$rpms_installed" == false ]]; then
        log_message "WARN" "Could not install release packages"
        if [[ -f "$backup_path/release-packages.list" ]]; then
            echo ""
            echo "Packages to install manually:"
            cat "$backup_path/release-packages.list"
        fi
    fi

    echo ""
    log_message "SUCCESS" "Minimal restore completed!"
    echo ""
    echo "Summary:"
    echo "  - Restored $restored_count deleted file(s)"
    if [[ "$rpms_installed" == true ]]; then
        echo "  - Original release packages installed"
    else
        echo "  - Release packages: MANUAL INSTALLATION REQUIRED"
    fi
    echo ""
    echo "Note: SUSE packages are still installed."
    echo "      Use --restore for full restore (removes SUSE packages)"
    echo ""
}

# List available backups
list_backups() {
    echo ""
    print_color blue "Available backups in $BACKUP_DIR:"
    echo ""

    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo "No backups found."
        return 1
    fi

    local count=0
    while IFS= read -r backup_dir; do
        if [[ -f "$backup_dir/metadata.json" ]]; then
            ((count++))
            local timestamp
            local os_info
            local has_rpms="No"

            timestamp=$(basename "$backup_dir")

            # Parse metadata
            if command -v jq &>/dev/null; then
                os_info=$(jq -r '"\(.os_name) \(.os_version)"' "$backup_dir/metadata.json" 2>/dev/null)
            else
                os_info=$(grep -o '"os_name"[^,]*' "$backup_dir/metadata.json" | cut -d'"' -f4)
                os_info="$os_info $(grep -o '"os_version"[^,]*' "$backup_dir/metadata.json" | cut -d'"' -f4)"
            fi

            # Check if RPMs exist
            if [[ -d "$backup_dir/rpms" ]] && [[ -n "$(ls -A "$backup_dir/rpms"/*.rpm 2>/dev/null)" ]]; then
                has_rpms="Yes"
            fi

            printf "  %-20s | OS: %-25s | RPMs: %s\n" "$timestamp" "$os_info" "$has_rpms"
        fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type d -name "[0-9]*_[0-9]*" | sort -r)

    if [[ $count -eq 0 ]]; then
        echo "No valid backups found."
        return 1
    fi

    echo ""
    echo "Total: $count backup(s)"

    if [[ -L "${BACKUP_DIR}/latest" ]]; then
        echo "Latest: $(basename "$(readlink -f "${BACKUP_DIR}/latest")")"
    fi
    echo ""
}

# Export backup to a portable archive
export_backup() {
    local backup_name="$1"
    local output_file="$2"

    local backup_path="${BACKUP_DIR}/${backup_name}"

    if [[ "$backup_name" == "latest" ]] && [[ -L "${BACKUP_DIR}/latest" ]]; then
        backup_path=$(readlink -f "${BACKUP_DIR}/latest")
        backup_name=$(basename "$backup_path")
    fi

    if [[ ! -d "$backup_path" ]]; then
        log_message "ERROR" "Backup not found: $backup_name"
        list_backups
        exit 1
    fi

    if [[ -z "$output_file" ]]; then
        output_file="liberate-backup-${backup_name}.tar.gz"
    fi

    log_message "INFO" "Exporting backup $backup_name to $output_file..."

    if [[ "$DRY_RUN" == true ]]; then
        log_message "DRY-RUN" "Would create archive $output_file"
        return 0
    fi

    tar -czf "$output_file" -C "$BACKUP_DIR" "$backup_name"

    if [[ -f "$output_file" ]]; then
        local size
        size=$(du -h "$output_file" | cut -f1)
        log_message "SUCCESS" "Backup exported to: $output_file ($size)"
        echo ""
        echo "To restore on another system:"
        echo "  1. Copy $output_file to the target system"
        echo "  2. Run: $SCRIPT_NAME --import-backup $output_file"
        echo "  3. Run: $SCRIPT_NAME --restore"
    else
        log_message "ERROR" "Failed to create archive"
        exit 1
    fi
}

# Import backup from archive
import_backup() {
    local archive_file="$1"

    if [[ ! -f "$archive_file" ]]; then
        log_message "ERROR" "Archive file not found: $archive_file"
        exit 1
    fi

    log_message "INFO" "Importing backup from $archive_file..."

    if [[ "$DRY_RUN" == true ]]; then
        log_message "DRY-RUN" "Would import backup from $archive_file"
        return 0
    fi

    mkdir -p "$BACKUP_DIR"

    # Extract archive
    if tar -xzf "$archive_file" -C "$BACKUP_DIR"; then
        # Find the extracted directory
        local extracted_dir
        extracted_dir=$(tar -tzf "$archive_file" | head -1 | cut -d'/' -f1)

        if [[ -d "${BACKUP_DIR}/${extracted_dir}" ]]; then
            # Update the latest symlink
            ln -sfn "${BACKUP_DIR}/${extracted_dir}" "${BACKUP_DIR}/latest"
            log_message "SUCCESS" "Backup imported: $extracted_dir"
            echo ""
            echo "To restore this backup, run:"
            echo "  $SCRIPT_NAME --restore"
        else
            log_message "ERROR" "Could not locate extracted backup"
            exit 1
        fi
    else
        log_message "ERROR" "Failed to extract archive"
        exit 1
    fi
}

# Restore original system from backup (full restore)
restore_original_system() {
    local backup_name="${RESTORE_BACKUP:-latest}"
    local backup_path

    log_message "INFO" "Starting full system restore..."

    # Resolve backup path
    if [[ "$backup_name" == "latest" ]]; then
        if [[ ! -L "${BACKUP_DIR}/latest" ]]; then
            log_message "ERROR" "No latest backup found"
            list_backups
            exit 1
        fi
        backup_path=$(readlink -f "${BACKUP_DIR}/latest")
    else
        backup_path="${BACKUP_DIR}/${backup_name}"
    fi

    if [[ ! -d "$backup_path" ]]; then
        log_message "ERROR" "Backup not found: $backup_path"
        list_backups
        exit 1
    fi

    log_message "INFO" "Restoring from backup: $backup_path"

    # Validate backup
    if [[ ! -f "$backup_path/metadata.json" ]]; then
        log_message "ERROR" "Invalid backup: metadata.json not found"
        exit 1
    fi

    # Load original OS info from metadata
    local orig_os_name orig_os_version
    if command -v jq &>/dev/null; then
        orig_os_name=$(jq -r '.os_name' "$backup_path/metadata.json")
        orig_os_version=$(jq -r '.os_version' "$backup_path/metadata.json")
    else
        orig_os_name=$(grep -o '"os_name"[^,]*' "$backup_path/metadata.json" | cut -d'"' -f4)
        orig_os_version=$(grep -o '"os_version"[^,]*' "$backup_path/metadata.json" | cut -d'"' -f4)
    fi

    echo ""
    print_color blue "Restore Information:"
    echo "  Backup: $(basename "$backup_path")"
    echo "  Original OS: $orig_os_name $orig_os_version"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        log_message "DRY-RUN" "Would restore system to $orig_os_name $orig_os_version"
        return 0
    fi

    if ! confirm "Restore system to $orig_os_name $orig_os_version?"; then
        log_message "INFO" "Restore cancelled by user"
        exit 0
    fi

    # Step 1: Remove SUSE release packages
    log_message "INFO" "Step 1/4: Removing SUSE release packages..."
    for suse_pkg in sll-release sll-logos sles_es-release sles_es-logos sles_es-release-server; do
        if rpm -q "$suse_pkg" &>/dev/null; then
            log_message "INFO" "Removing $suse_pkg..."
            rpm -e --nodeps "$suse_pkg" 2>/dev/null || true
        fi
    done

    # Step 2: Restore repository configuration
    log_message "INFO" "Step 2/4: Restoring repository configuration..."

    # Remove SUSE repos
    rm -f /etc/yum.repos.d/SLL*.repo /etc/yum.repos.d/sles*.repo 2>/dev/null || true

    # Restore original repos
    if [[ -d "$backup_path/repos" ]] && [[ -n "$(ls -A "$backup_path/repos" 2>/dev/null)" ]]; then
        cp -a "$backup_path/repos/"* /etc/yum.repos.d/
        log_message "INFO" "Repository files restored"
    else
        log_message "WARN" "No repository files in backup"
    fi

    # Step 3: Install original release packages
    log_message "INFO" "Step 3/4: Installing original release packages..."

    local rpm_dir="${backup_path}/rpms"
    local rpms_installed=false

    if [[ -d "$rpm_dir" ]] && [[ -n "$(ls -A "$rpm_dir"/*.rpm 2>/dev/null)" ]]; then
        log_message "INFO" "Installing RPMs from backup..."

        # Verify checksums if available
        if [[ -f "$rpm_dir/SHA256SUMS" ]]; then
            log_message "INFO" "Verifying RPM checksums..."
            (cd "$rpm_dir" && sha256sum -c SHA256SUMS) || {
                log_message "WARN" "Checksum verification failed for some RPMs"
            }
        fi

        # Install the RPMs
        if rpm -Uvh --force "$rpm_dir"/*.rpm 2>&1 | tee -a "$LOG_FILE"; then
            rpms_installed=true
            log_message "SUCCESS" "Release packages installed from backup"
        else
            log_message "WARN" "Some RPMs failed to install"
        fi
    fi

    # If RPMs not available, try to install from repos
    if [[ "$rpms_installed" == false ]]; then
        log_message "INFO" "RPMs not found in backup, attempting to install from repositories..."

        if [[ -f "$backup_path/release-packages.list" ]]; then
            local pkg_list
            pkg_list=$(cat "$backup_path/release-packages.list" | tr '\n' ' ')

            # Clean dnf/yum cache
            if command -v dnf &>/dev/null; then
                dnf clean all &>/dev/null
                dnf install -y $pkg_list 2>&1 | tee -a "$LOG_FILE" && rpms_installed=true
            elif command -v yum &>/dev/null; then
                yum clean all &>/dev/null
                yum install -y $pkg_list 2>&1 | tee -a "$LOG_FILE" && rpms_installed=true
            fi
        fi
    fi

    if [[ "$rpms_installed" == false ]]; then
        log_message "WARN" "Could not automatically install release packages"
        log_message "WARN" "Manual installation may be required"
        if [[ -f "$backup_path/release-packages.list" ]]; then
            echo ""
            echo "Packages to install manually:"
            cat "$backup_path/release-packages.list"
            echo ""
        fi
    fi

    # Step 4: Restore configuration files
    log_message "INFO" "Step 4/4: Restoring configuration files..."

    # Restore protected.d
    if [[ -d "$backup_path/dnf-yum-config/protected.d" ]]; then
        mkdir -p /etc/dnf/protected.d
        cp -a "$backup_path/dnf-yum-config/protected.d/"* /etc/dnf/protected.d/ 2>/dev/null || true
    fi

    # Restore dnf.conf if it existed
    if [[ -f "$backup_path/dnf-yum-config/dnf.conf" ]]; then
        cp -a "$backup_path/dnf-yum-config/dnf.conf" /etc/dnf/ 2>/dev/null || true
    fi

    # Remove liberated marker
    if [[ -f "$LIBERATED_MARKER" ]]; then
        rm -f "$LIBERATED_MARKER"
        log_message "INFO" "Removed liberated marker"
    fi

    # Clean package manager cache
    log_message "INFO" "Cleaning package manager cache..."
    if command -v dnf &>/dev/null; then
        dnf clean all &>/dev/null
    elif command -v yum &>/dev/null; then
        yum clean all &>/dev/null
    fi

    echo ""
    log_message "SUCCESS" "System restore completed!"
    echo ""
    echo "Summary:"
    echo "  - SUSE release packages removed"
    echo "  - Original repository configuration restored"
    if [[ "$rpms_installed" == true ]]; then
        echo "  - Original release packages installed"
    else
        echo "  - Original release packages: MANUAL INSTALLATION REQUIRED"
    fi
    echo "  - Liberated marker removed"
    echo ""
    print_color yellow "A system reboot is recommended to complete the restore."
    echo ""
}

# =============================================================================
# Liberation Functions - EL9
# =============================================================================

liberate_el9() {
    log_message "INFO" "Starting EL9 liberation process..."

    local release_pkg=""
    local os_id=""

    # shellcheck source=/dev/null
    source /etc/os-release
    os_id="${ID:-}"

    # Determine which release package to remove
    case "$os_id" in
        rocky)
            release_pkg="rocky-release"
            ;;
        almalinux)
            release_pkg="almalinux-release"
            ;;
        ol|oracle)
            release_pkg="oraclelinux-release"
            ;;
        centos)
            release_pkg="centos-stream-release"
            ;;
        rhel)
            release_pkg="redhat-release"
            ;;
        eurolinux)
            release_pkg="eurolinux-release"
            ;;
        *)
            log_message "ERROR" "Unknown EL9 distribution: $os_id"
            exit 1
            ;;
    esac

    if confirm "Remove $release_pkg and install SUSE Liberty Linux?"; then
        # Remove original release package
        if rpm -q "$release_pkg" &>/dev/null; then
            log_message "INFO" "Removing $release_pkg..."
            run_cmd "rpm -e --nodeps $release_pkg"
        else
            log_message "WARN" "Package $release_pkg not found, skipping removal"
        fi

        # Remove redhat-release directory if exists
        if [[ -d /usr/share/redhat-release ]]; then
            log_message "INFO" "Removing /usr/share/redhat-release..."
            run_cmd "rm -rf /usr/share/redhat-release"
        fi

        # Remove protected.d configuration
        if [[ -f /etc/dnf/protected.d/redhat-release.conf ]]; then
            log_message "INFO" "Removing redhat-release.conf from protected.d..."
            run_cmd "rm -f /etc/dnf/protected.d/redhat-release.conf"
        fi

        # Install SUSE Liberty Linux release package
        log_message "INFO" "Installing sll-release..."
        run_cmd "dnf install -y sll-release"

        # Install logos if requested
        if [[ "$INSTALL_LOGOS" == true ]]; then
            log_message "INFO" "Installing sll-logos..."
            run_cmd "dnf install -y sll-logos" || log_message "WARN" "Could not install sll-logos"
        fi

        # Reinstall all packages if requested
        if [[ "$REINSTALL_PACKAGES" == true ]]; then
            log_message "INFO" "Reinstalling all packages from SUSE repos (this may take a while)..."
            if confirm "Proceed with package reinstallation?"; then
                run_cmd "dnf -x 'venv-salt-minion' reinstall '*' -y >> $DNF_MIGRATION_LOG 2>&1" || \
                    log_message "WARN" "Some packages could not be reinstalled"
            fi
        fi
    else
        log_message "INFO" "Liberation cancelled by user"
        exit 0
    fi

    log_message "SUCCESS" "EL9 liberation completed"
}

# =============================================================================
# Liberation Functions - EL8
# =============================================================================

liberate_el8() {
    log_message "INFO" "Starting EL8 liberation process..."

    local release_pkg=""
    local os_id=""
    local pkg_mgr="dnf"

    # Use yum if dnf is not available
    if ! command -v dnf &>/dev/null; then
        pkg_mgr="yum"
    fi

    # shellcheck source=/dev/null
    source /etc/os-release
    os_id="${ID:-}"

    # Determine which release package to remove
    case "$os_id" in
        rocky)
            release_pkg="rocky-release"
            ;;
        almalinux)
            release_pkg="almalinux-release"
            ;;
        ol|oracle)
            release_pkg="oraclelinux-release"
            ;;
        centos)
            if grep -qi "stream" /etc/centos-release 2>/dev/null; then
                release_pkg="centos-stream-release"
            else
                release_pkg="centos-release"
            fi
            ;;
        rhel)
            release_pkg="redhat-release"
            ;;
        eurolinux)
            release_pkg="eurolinux-release"
            ;;
        *)
            log_message "ERROR" "Unknown EL8 distribution: $os_id"
            exit 1
            ;;
    esac

    if confirm "Remove $release_pkg and install SLES Expanded Support?"; then
        # Remove original release package
        if rpm -q "$release_pkg" &>/dev/null; then
            log_message "INFO" "Removing $release_pkg..."
            run_cmd "rpm -e --nodeps $release_pkg"
        else
            log_message "WARN" "Package $release_pkg not found, skipping removal"
        fi

        # Remove redhat-release directory if exists
        if [[ -d /usr/share/redhat-release ]]; then
            log_message "INFO" "Removing /usr/share/redhat-release..."
            run_cmd "rm -rf /usr/share/redhat-release"
        fi

        # Remove protected.d configuration
        if [[ -f /etc/dnf/protected.d/redhat-release.conf ]]; then
            log_message "INFO" "Removing redhat-release.conf from protected.d..."
            run_cmd "rm -f /etc/dnf/protected.d/redhat-release.conf"
        fi

        # Install SLES Expanded Support release package
        log_message "INFO" "Installing sles_es-release..."
        run_cmd "$pkg_mgr install -y sles_es-release"

        # Install logos if requested
        if [[ "$INSTALL_LOGOS" == true ]]; then
            log_message "INFO" "Installing sles_es-logos..."
            run_cmd "$pkg_mgr install -y sles_es-logos" || log_message "WARN" "Could not install sles_es-logos"
        fi

        # Reinstall all packages if requested
        if [[ "$REINSTALL_PACKAGES" == true ]]; then
            log_message "INFO" "Reinstalling all packages from SUSE repos (this may take a while)..."
            if confirm "Proceed with package reinstallation?"; then
                run_cmd "$pkg_mgr -x 'venv-salt-minion' -x 'salt-minion' reinstall '*' -y >> $YUM_MIGRATION_LOG 2>&1" || \
                    log_message "WARN" "Some packages could not be reinstalled"
            fi
        fi
    else
        log_message "INFO" "Liberation cancelled by user"
        exit 0
    fi

    log_message "SUCCESS" "EL8 liberation completed"
}

# =============================================================================
# Liberation Functions - EL7
# =============================================================================

liberate_el7() {
    log_message "INFO" "Starting EL7 liberation process..."

    local release_pkg=""
    local os_id=""

    # shellcheck source=/dev/null
    source /etc/os-release
    os_id="${ID:-}"

    # Determine which release package to remove
    case "$os_id" in
        ol|oracle)
            release_pkg="oraclelinux-release-el7"
            ;;
        centos)
            release_pkg="centos-release"
            ;;
        rhel)
            release_pkg="redhat-release-server"
            ;;
        eurolinux)
            release_pkg="eurolinux-release"
            ;;
        *)
            log_message "ERROR" "Unknown EL7 distribution: $os_id"
            exit 1
            ;;
    esac

    if confirm "Remove $release_pkg and install SLES Expanded Support?"; then
        # Remove original release package
        if rpm -q "$release_pkg" &>/dev/null; then
            log_message "INFO" "Removing $release_pkg..."
            run_cmd "rpm -e --nodeps $release_pkg"
        else
            log_message "WARN" "Package $release_pkg not found, skipping removal"
        fi

        # Remove redhat-release directory if exists
        if [[ -d /usr/share/redhat-release ]]; then
            log_message "INFO" "Removing /usr/share/redhat-release..."
            run_cmd "rm -rf /usr/share/redhat-release"
        fi

        # Install SLES Expanded Support release package
        log_message "INFO" "Installing sles_es-release-server..."
        run_cmd "yum install -y sles_es-release-server"

        # Install logos if requested
        if [[ "$INSTALL_LOGOS" == true ]]; then
            log_message "INFO" "Installing sles_es-logos..."
            run_cmd "yum install -y sles_es-logos" || log_message "WARN" "Could not install sles_es-logos"
        fi

        # EL7 specific fixes
        log_message "INFO" "Applying EL7 specific fixes..."

        # Upgrade anaconda-core if installed
        if rpm -q anaconda-core &>/dev/null; then
            log_message "INFO" "Upgrading anaconda-core..."
            run_cmd "yum -y upgrade anaconda-core" || log_message "WARN" "Could not upgrade anaconda-core"
        fi

        # Reinstall libreport-plugin-bugzilla if installed
        if rpm -q libreport-plugin-bugzilla &>/dev/null; then
            log_message "INFO" "Reinstalling libreport-plugin-bugzilla..."
            run_cmd "yum -y reinstall libreport-plugin-bugzilla --obsoletes" || \
                log_message "WARN" "Could not reinstall libreport-plugin-bugzilla"
        fi

        # Reinstall all packages if requested
        if [[ "$REINSTALL_PACKAGES" == true ]]; then
            log_message "INFO" "Reinstalling all packages from SUSE repos (this may take a while)..."
            if confirm "Proceed with package reinstallation?"; then
                local all_packages
                all_packages=$(rpm -qa)
                run_cmd "yum -x 'venv-salt-minion' -x 'salt-minion' -x 'libreport-plugin-bugzilla' -y reinstall $all_packages --obsoletes >> $YUM_MIGRATION_LOG 2>&1" || \
                    log_message "WARN" "Some packages could not be reinstalled"
            fi
        fi
    else
        log_message "INFO" "Liberation cancelled by user"
        exit 0
    fi

    log_message "SUCCESS" "EL7 liberation completed"
}

# =============================================================================
# Post-Liberation Functions
# =============================================================================

# Create liberated marker file
create_liberated_marker() {
    log_message "INFO" "Creating liberated marker file..."

    local liberated_date
    liberated_date="$(date '+%Y-%m-%d %H:%M:%S')"

    if [[ "$DRY_RUN" == true ]]; then
        log_message "DRY-RUN" "Would create $LIBERATED_MARKER"
        return 0
    fi

    mkdir -p "$(dirname "$LIBERATED_MARKER")"

    cat > "$LIBERATED_MARKER" << EOF
# SUSE Liberation marker file
# Created by liberate.sh v$SCRIPT_VERSION
LIBERATED="true"
LIBERATED_FROM="$OS_NAME $OS_VERSION"
LIBERATED_DATE="$liberated_date"
LIBERATED_REINSTALLED="$REINSTALL_PACKAGES"
EOF

    log_message "SUCCESS" "Liberated marker created at $LIBERATED_MARKER"
}

# Verify migration was successful
verify_migration() {
    log_message "INFO" "Verifying migration..."

    local errors=0

    # Check liberated marker
    if [[ ! -f "$LIBERATED_MARKER" ]]; then
        log_message "WARN" "Liberated marker not found"
        ((errors++))
    fi

    # Check os-release for SUSE
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        case "${ID:-}" in
            sll|sles|suse)
                log_message "INFO" "/etc/os-release shows SUSE distribution"
                ;;
            *)
                log_message "WARN" "/etc/os-release does not show SUSE (ID=${ID:-unknown})"
                ((errors++))
                ;;
        esac
    fi

    # Check for SUSE release package
    if rpm -q sll-release &>/dev/null; then
        log_message "INFO" "sll-release package is installed"
    elif rpm -q sles_es-release &>/dev/null; then
        log_message "INFO" "sles_es-release package is installed"
    elif rpm -q sles_es-release-server &>/dev/null; then
        log_message "INFO" "sles_es-release-server package is installed"
    else
        log_message "WARN" "No SUSE release package found"
        ((errors++))
    fi

    if [[ $errors -eq 0 ]]; then
        log_message "SUCCESS" "Migration verification passed"
        return 0
    else
        log_message "WARN" "Migration verification completed with $errors warning(s)"
        return 1
    fi
}

# Generate migration report
generate_report() {
    local report_file="/var/log/liberate_report_$(date '+%Y%m%d_%H%M%S').txt"

    log_message "INFO" "Generating migration report..."

    if [[ "$DRY_RUN" == true ]]; then
        log_message "DRY-RUN" "Would generate report at $report_file"
        return 0
    fi

    {
        echo "=========================================="
        echo "SUSE Liberation Migration Report"
        echo "=========================================="
        echo ""
        echo "Report generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Script version: $SCRIPT_VERSION"
        echo ""
        echo "-- Original System --"
        echo "Distribution: $OS_NAME"
        echo "Version: $OS_VERSION"
        echo ""
        echo "-- Current System --"
        if [[ -f /etc/os-release ]]; then
            # shellcheck source=/dev/null
            source /etc/os-release
            echo "Name: ${PRETTY_NAME:-unknown}"
            echo "ID: ${ID:-unknown}"
            echo "Version: ${VERSION_ID:-unknown}"
        fi
        echo ""
        echo "-- Kernel --"
        echo "$(uname -a)"
        echo ""
        echo "-- Installed SUSE Packages --"
        rpm -qa | grep -E '(sll|sles_es|suse)' | sort || echo "None found"
        echo ""
        echo "-- Liberated Marker --"
        if [[ -f "$LIBERATED_MARKER" ]]; then
            cat "$LIBERATED_MARKER"
        else
            echo "Not found"
        fi
        echo ""
        echo "-- Backup Location --"
        if [[ -n "${CURRENT_BACKUP_DIR:-}" ]]; then
            echo "$CURRENT_BACKUP_DIR"
        elif [[ -L "${BACKUP_DIR}/latest" ]]; then
            readlink -f "${BACKUP_DIR}/latest"
        else
            echo "No backup created"
        fi
        echo ""
        echo "-- Migration Log --"
        if [[ -f "$LOG_FILE" ]]; then
            tail -50 "$LOG_FILE"
        else
            echo "Log file not found"
        fi
        echo ""
        echo "=========================================="
        echo "End of Report"
        echo "=========================================="
    } > "$report_file"

    log_message "SUCCESS" "Report saved to $report_file"

    # Also display summary to stdout
    echo ""
    print_color green "=========================================="
    print_color green "Migration Summary"
    print_color green "=========================================="
    echo "Original OS: $OS_NAME $OS_VERSION"
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        echo "Current OS: ${PRETTY_NAME:-unknown}"
    fi
    echo "Report file: $report_file"
    echo "Log file: $LOG_FILE"
    if [[ -n "${CURRENT_BACKUP_DIR:-}" ]]; then
        echo "Backup: $CURRENT_BACKUP_DIR"
    fi
    print_color green "=========================================="
}

# =============================================================================
# Help and Usage
# =============================================================================

show_help() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION - Convert Enterprise Linux to SUSE Liberty Linux

Usage: $SCRIPT_NAME [OPTIONS]

This script converts Enterprise Linux distributions (Rocky, AlmaLinux, Oracle Linux,
CentOS, RHEL, EuroLinux) to SUSE Liberty Linux (EL9) or SLES Expanded Support (EL7/8).

OPTIONS:
  Main options:
    --reinstall-packages    Reinstall all packages from SUSE repositories
    --install-logos         Install SUSE branding/logos packages
    --dry-run               Show commands without executing them
    --help, -h              Show this help message

  Backup options:
    --no-backup             Disable automatic backup before migration
    --backup-dir <path>     Set backup directory (default: $DEFAULT_BACKUP_DIR)
    --list-backups          List all available backups

  Restore options:
    --rollback              Restore repository configs only (partial restore)
    --restore [name]        Full system restore (removes SUSE, reinstalls original)
                            Use 'latest' or backup timestamp (e.g., 20240115_103045)
    --restore-minimal [name] Restore only deleted files and release package
                            Does NOT remove SUSE packages (lighter restore)

  Portability options:
    --export-backup <name>  Export a backup to portable archive (.tar.gz)
    --import-backup <file>  Import a backup from archive

  Other options:
    --interactive           Enable interactive mode with confirmations
    --force                 Force migration even if already liberated
    --report                Generate detailed migration report
    --verbose, -v           Show detailed output

SUPPORTED DISTRIBUTIONS:
  - Rocky Linux 8, 9
  - AlmaLinux 8, 9
  - Oracle Linux 7, 8, 9
  - CentOS 7, CentOS Stream 8, 9
  - RHEL 7, 8, 9
  - EuroLinux 7, 8, 9

PREREQUISITES:
  - SUSE repositories must be configured before running this script
  - Root privileges required
  - At least 100 MB free disk space for backup

EXAMPLES:
  # Basic migration with backup (RPMs are automatically saved)
  $SCRIPT_NAME

  # Migration with package reinstallation and logos
  $SCRIPT_NAME --reinstall-packages --install-logos

  # Interactive dry-run to preview changes
  $SCRIPT_NAME --interactive --dry-run --verbose

  # List available backups
  $SCRIPT_NAME --list-backups

  # Full restore to original distribution (uses latest backup)
  $SCRIPT_NAME --restore

  # Minimal restore (only deleted files and release package, keeps SUSE)
  $SCRIPT_NAME --restore-minimal

  # Restore from a specific backup
  $SCRIPT_NAME --restore 20240115_103045

  # Export backup for use on another system
  $SCRIPT_NAME --export-backup latest

  # Import and restore backup on another system
  $SCRIPT_NAME --import-backup liberate-backup-20240115_103045.tar.gz
  $SCRIPT_NAME --restore

BACKUP CONTENTS:
  The backup includes:
  - Release RPM packages (for offline restore)
  - Deleted files (/usr/share/redhat-release, /etc/dnf/protected.d/*, etc.)
  - Repository configuration files
  - Package list (all installed packages)
  - DNF/YUM configuration
  - System metadata (OS info, kernel, etc.)

FILES:
  $LIBERATED_MARKER      Migration marker file
  $LOG_FILE              Main log file
  $DEFAULT_BACKUP_DIR    Backup directory
  $DNF_MIGRATION_LOG     DNF reinstall log (EL9)
  $YUM_MIGRATION_LOG     YUM reinstall log (EL7/8)

For more information, see the documentation or contact your SUSE representative.
EOF
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reinstall-packages)
                REINSTALL_PACKAGES=true
                shift
                ;;
            --install-logos)
                INSTALL_LOGOS=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-backup)
                NO_BACKUP=true
                shift
                ;;
            --backup-dir)
                if [[ -z "${2:-}" ]]; then
                    log_message "ERROR" "--backup-dir requires a path argument"
                    exit 1
                fi
                BACKUP_DIR="$2"
                shift 2
                ;;
            --list-backups)
                LIST_BACKUPS=true
                shift
                ;;
            --rollback)
                DO_ROLLBACK=true
                shift
                ;;
            --restore)
                DO_RESTORE=true
                # Check if next argument is a backup name (not another option)
                if [[ -n "${2:-}" ]] && [[ ! "$2" =~ ^-- ]]; then
                    RESTORE_BACKUP="$2"
                    shift
                else
                    RESTORE_BACKUP="latest"
                fi
                shift
                ;;
            --restore-minimal)
                DO_RESTORE_MINIMAL=true
                # Check if next argument is a backup name (not another option)
                if [[ -n "${2:-}" ]] && [[ ! "$2" =~ ^-- ]]; then
                    RESTORE_BACKUP="$2"
                    shift
                else
                    RESTORE_BACKUP="latest"
                fi
                shift
                ;;
            --export-backup)
                if [[ -z "${2:-}" ]]; then
                    log_message "ERROR" "--export-backup requires a backup name"
                    exit 1
                fi
                EXPORT_BACKUP="$2"
                shift 2
                ;;
            --import-backup)
                if [[ -z "${2:-}" ]]; then
                    log_message "ERROR" "--import-backup requires an archive file"
                    exit 1
                fi
                IMPORT_BACKUP="$2"
                shift 2
                ;;
            --interactive)
                INTERACTIVE=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --report)
                GENERATE_REPORT=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_message "ERROR" "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Banner
    echo ""
    print_color blue "=========================================="
    print_color blue "  SUSE Liberation Script v$SCRIPT_VERSION"
    print_color blue "=========================================="
    echo ""

    # Check root privileges
    check_root

    # Handle list-backups mode (no detection needed)
    if [[ "$LIST_BACKUPS" == true ]]; then
        list_backups
        exit $?
    fi

    # Handle import-backup mode
    if [[ -n "$IMPORT_BACKUP" ]]; then
        import_backup "$IMPORT_BACKUP"
        exit $?
    fi

    # Handle export-backup mode
    if [[ -n "$EXPORT_BACKUP" ]]; then
        export_backup "$EXPORT_BACKUP" ""
        exit $?
    fi

    # Handle restore mode (full restore)
    if [[ "$DO_RESTORE" == true ]]; then
        restore_original_system
        exit $?
    fi

    # Handle restore-minimal mode (only deleted files and release package)
    if [[ "$DO_RESTORE_MINIMAL" == true ]]; then
        restore_minimal
        exit $?
    fi

    # Handle rollback mode (partial restore)
    if [[ "$DO_ROLLBACK" == true ]]; then
        rollback
        exit $?
    fi

    # Detect system
    detect_os
    detect_version

    # Check if already liberated
    check_already_liberated

    # Check prerequisites
    check_prerequisites

    # Display summary
    echo ""
    echo "Detected: $OS_NAME $OS_VERSION"
    echo "Target: SUSE Liberty Linux / SLES Expanded Support"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        print_color yellow "DRY-RUN MODE: No changes will be made"
        echo ""
    fi

    # Confirm in interactive mode
    if ! confirm "Proceed with migration?"; then
        log_message "INFO" "Migration cancelled by user"
        exit 0
    fi

    # Create backup
    create_backup

    # Perform liberation based on version
    case "$OS_VERSION_MAJOR" in
        9)
            liberate_el9
            ;;
        8)
            liberate_el8
            ;;
        7)
            liberate_el7
            ;;
        *)
            log_message "ERROR" "Unsupported version: $OS_VERSION_MAJOR"
            exit 1
            ;;
    esac

    # Create marker file
    create_liberated_marker

    # Verify migration
    verify_migration

    # Cleanup old backups
    cleanup_backup 5

    # Generate report if requested
    if [[ "$GENERATE_REPORT" == true ]]; then
        generate_report
    fi

    # Final message
    echo ""
    log_message "SUCCESS" "Migration completed successfully!"
    echo ""
    echo "Please review the log file: $LOG_FILE"
    if [[ -n "${CURRENT_BACKUP_DIR:-}" ]] && [[ "$NO_BACKUP" != true ]]; then
        echo "Backup saved to: $CURRENT_BACKUP_DIR"
    fi
    echo ""
    print_color yellow "A system reboot is recommended to complete the migration."
    echo ""
}

# =============================================================================
# Entry Point
# =============================================================================

# Run main function with all arguments
main "$@"
