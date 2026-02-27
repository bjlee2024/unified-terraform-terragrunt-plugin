#!/usr/bin/env bash
#
# setup.sh - CLI tool detection and installation for unified-terraform-terragrunt plugin
#
# Usage:
#   ./setup.sh          Interactive mode (prompts before install)
#   ./setup.sh --check  Check status only (no installs)
#   ./setup.sh --auto   Non-interactive mode (auto-install, for CI/CD)
#   ./setup.sh --help   Show usage
#

set -euo pipefail

# ==============================================================================
# A. Constants & Configuration
# ==============================================================================

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="$(basename "$0")"

# Minimum versions from marketplace.json / SKILL.md
readonly MIN_TERRAFORM_VERSION="0.13.0"
readonly MIN_TERRAGRUNT_VERSION="0.38.0"
readonly RECOMMENDED_TERRAFORM_VERSION="1.6.0"

# Fallback versions when API calls fail (rate limits, network issues)
readonly FALLBACK_TERRAFORM_VERSION="1.11.4"
readonly FALLBACK_TERRAGRUNT_VERSION="0.77.20"

# Colors (respect NO_COLOR: https://no-color.org/)
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[0;33m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly BOLD='\033[1m'
    readonly DIM='\033[2m'
    readonly RESET='\033[0m'
else
    readonly RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' RESET=''
fi

# Mode flags
CHECK_ONLY=false
AUTO_MODE=false

# Result tracking
declare -A TOOL_STATUS=()
declare -A TOOL_VERSION=()
INSTALL_ERRORS=()

# ==============================================================================
# B. Utility Functions
# ==============================================================================

log_info() {
    printf "${BLUE}[INFO]${RESET} %s\n" "$*"
}

log_success() {
    printf "${GREEN}[OK]${RESET}   %s\n" "$*"
}

log_warn() {
    printf "${YELLOW}[WARN]${RESET} %s\n" "$*"
}

log_error() {
    printf "${RED}[ERR]${RESET}  %s\n" "$*" >&2
}

log_step() {
    printf "\n${BOLD}${CYAN}==> %s${RESET}\n" "$*"
}

command_exists() {
    command -v "$1" &>/dev/null
}

# Get version string from a tool.
# Handles various output formats: "Terraform v1.11.4", "terragrunt version v0.77.20"
get_version() {
    local tool="$1"
    local raw_output

    case "$tool" in
        terraform)
            raw_output="$(terraform version -json 2>/dev/null | grep -o '"terraform_version": *"[^"]*"' | head -1 | grep -o '[0-9][0-9.]*' || true)"
            if [[ -z "$raw_output" ]]; then
                raw_output="$(terraform version 2>/dev/null | head -1 | grep -o '[0-9][0-9.]*' || true)"
            fi
            ;;
        terragrunt)
            raw_output="$(terragrunt --version 2>/dev/null | head -1 | grep -o '[0-9][0-9.]*' || true)"
            ;;
        *)
            raw_output="$("$tool" --version 2>/dev/null | head -1 | grep -o '[0-9][0-9.]*' || true)"
            ;;
    esac

    echo "$raw_output"
}

# Compare two semver strings: returns 0 if $1 >= $2
version_gte() {
    local ver1="$1"
    local ver2="$2"

    if [[ "$ver1" == "$ver2" ]]; then
        return 0
    fi

    # Try sort -V first (GNU coreutils)
    if echo "" | sort -V &>/dev/null; then
        local higher
        higher="$(printf '%s\n%s\n' "$ver1" "$ver2" | sort -V | tail -1)"
        [[ "$higher" == "$ver1" ]]
        return $?
    fi

    # Fallback: manual comparison
    local IFS='.'
    local -a v1=($ver1) v2=($ver2)
    local i

    for i in 0 1 2; do
        local n1="${v1[$i]:-0}"
        local n2="${v2[$i]:-0}"
        if (( n1 > n2 )); then
            return 0
        elif (( n1 < n2 )); then
            return 1
        fi
    done

    return 0
}

# Interactive confirmation. Returns 0 for yes, 1 for no.
# In auto mode, always returns 0.
confirm() {
    local prompt="$1"

    if [[ "$AUTO_MODE" == true ]]; then
        return 0
    fi

    printf "${BOLD}%s [Y/n]${RESET} " "$prompt"
    local answer
    read -r answer
    case "${answer,,}" in
        "" | y | yes) return 0 ;;
        *) return 1 ;;
    esac
}

# Detect platform: returns "macos" or "linux"
detect_platform() {
    local os
    os="$(uname -s)"
    case "$os" in
        Darwin) echo "macos" ;;
        Linux)  echo "linux" ;;
        *)
            log_error "Unsupported platform: $os"
            exit 1
            ;;
    esac
}

# Detect architecture: returns "amd64" or "arm64"
detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64)       echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *)
            log_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

# Fetch latest release version from GitHub API
# Usage: fetch_latest_github_release "gruntwork-io/terragrunt"
fetch_latest_github_release() {
    local repo="$1"
    local version=""

    if command_exists curl; then
        version="$(curl -fsSL --max-time 10 \
            "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
            | grep '"tag_name"' | head -1 | grep -o '[0-9][0-9.]*' || true)"
    elif command_exists wget; then
        version="$(wget -qO- --timeout=10 \
            "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
            | grep '"tag_name"' | head -1 | grep -o '[0-9][0-9.]*' || true)"
    fi

    echo "$version"
}

# Fetch latest Terraform version from HashiCorp checkpoint API
fetch_latest_terraform_version() {
    local version=""

    # Try HashiCorp checkpoint API first
    if command_exists curl; then
        version="$(curl -fsSL --max-time 10 \
            "https://checkpoint-api.hashicorp.com/v1/check/terraform" 2>/dev/null \
            | grep -o '"current_version":"[^"]*"' | grep -o '[0-9][0-9.]*' || true)"
    elif command_exists wget; then
        version="$(wget -qO- --timeout=10 \
            "https://checkpoint-api.hashicorp.com/v1/check/terraform" 2>/dev/null \
            | grep -o '"current_version":"[^"]*"' | grep -o '[0-9][0-9.]*' || true)"
    fi

    # Fallback to GitHub releases
    if [[ -z "$version" ]]; then
        version="$(fetch_latest_github_release "hashicorp/terraform")"
    fi

    echo "$version"
}

# Ensure we have a download tool
ensure_download_tool() {
    if command_exists curl; then
        return 0
    elif command_exists wget; then
        return 0
    else
        log_error "Neither curl nor wget found. Please install one of them."
        return 1
    fi
}

# Download a file. Usage: download_file URL DEST
download_file() {
    local url="$1"
    local dest="$2"

    if command_exists curl; then
        curl -fsSL --max-time 120 -o "$dest" "$url"
    elif command_exists wget; then
        wget -q --timeout=120 -O "$dest" "$url"
    else
        log_error "No download tool available (curl/wget)"
        return 1
    fi
}

# Get install directory with sudo fallback
get_install_dir() {
    if [[ -w "/usr/local/bin" ]]; then
        echo "/usr/local/bin"
    elif sudo -n true 2>/dev/null; then
        echo "/usr/local/bin"
    else
        local local_bin="$HOME/.local/bin"
        mkdir -p "$local_bin"
        echo "$local_bin"
    fi
}

# Install binary to target directory, using sudo if needed
install_binary() {
    local src="$1"
    local dest_dir="$2"
    local dest_name="$3"
    local dest_path="${dest_dir}/${dest_name}"

    if [[ -w "$dest_dir" ]]; then
        mv "$src" "$dest_path"
        chmod +x "$dest_path"
    else
        log_info "Requires elevated permissions to install to $dest_dir"
        sudo mv "$src" "$dest_path"
        sudo chmod +x "$dest_path"
    fi
}

# ==============================================================================
# C. Install Functions
# ==============================================================================

install_terraform() {
    local platform="$1"
    local arch="$2"

    log_step "Installing Terraform"

    # Resolve latest version
    log_info "Fetching latest Terraform version..."
    local version
    version="$(fetch_latest_terraform_version)"

    if [[ -z "$version" ]]; then
        log_warn "Could not fetch latest version, using fallback: $FALLBACK_TERRAFORM_VERSION"
        version="$FALLBACK_TERRAFORM_VERSION"
    fi

    log_info "Latest stable version: $version"

    case "$platform" in
        macos)
            install_terraform_macos "$version"
            ;;
        linux)
            install_terraform_linux "$version" "$arch"
            ;;
    esac
}

install_terraform_macos() {
    local version="$1"

    if command_exists brew; then
        log_info "Installing Terraform via Homebrew..."
        brew tap hashicorp/tap 2>/dev/null || true
        brew install hashicorp/tap/terraform 2>/dev/null || brew upgrade hashicorp/tap/terraform 2>/dev/null || true
    else
        log_warn "Homebrew not found, falling back to binary download"
        install_terraform_binary "$version" "macos" "$(detect_arch)"
    fi
}

install_terraform_linux() {
    local version="$1"
    local arch="$2"

    install_terraform_binary "$version" "linux" "$arch"
}

install_terraform_binary() {
    local version="$1"
    local os="$2"
    local arch="$3"

    # Map OS name for HashiCorp download URL
    local dl_os="$os"
    if [[ "$os" == "macos" ]]; then
        dl_os="darwin"
    fi

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" RETURN

    local zip_url="https://releases.hashicorp.com/terraform/${version}/terraform_${version}_${dl_os}_${arch}.zip"
    local zip_path="${tmpdir}/terraform.zip"

    log_info "Downloading Terraform $version from releases.hashicorp.com..."
    if ! download_file "$zip_url" "$zip_path"; then
        log_error "Failed to download Terraform"
        return 1
    fi

    log_info "Extracting..."
    if command_exists unzip; then
        unzip -q -o "$zip_path" -d "$tmpdir"
    else
        log_error "unzip is required but not found. Please install unzip."
        return 1
    fi

    local install_dir
    install_dir="$(get_install_dir)"
    log_info "Installing to $install_dir..."
    install_binary "${tmpdir}/terraform" "$install_dir" "terraform"

    # Verify
    if command_exists terraform; then
        log_success "Terraform $(get_version terraform) installed to $install_dir"
    else
        if [[ "$install_dir" == "$HOME/.local/bin" ]]; then
            log_warn "Terraform installed to $install_dir"
            log_warn "Make sure $install_dir is in your PATH:"
            log_warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        fi
    fi
}

install_terragrunt() {
    local platform="$1"
    local arch="$2"

    log_step "Installing Terragrunt"

    # Resolve latest version
    log_info "Fetching latest Terragrunt version..."
    local version
    version="$(fetch_latest_github_release "gruntwork-io/terragrunt")"

    if [[ -z "$version" ]]; then
        log_warn "Could not fetch latest version, using fallback: $FALLBACK_TERRAGRUNT_VERSION"
        version="$FALLBACK_TERRAGRUNT_VERSION"
    fi

    log_info "Latest stable version: $version"

    case "$platform" in
        macos)
            install_terragrunt_macos "$version"
            ;;
        linux)
            install_terragrunt_linux "$version" "$arch"
            ;;
    esac
}

install_terragrunt_macos() {
    local version="$1"

    if command_exists brew; then
        log_info "Installing Terragrunt via Homebrew..."
        brew install terragrunt 2>/dev/null || brew upgrade terragrunt 2>/dev/null || true
    else
        log_warn "Homebrew not found, falling back to binary download"
        install_terragrunt_binary "$version" "macos" "$(detect_arch)"
    fi
}

install_terragrunt_linux() {
    local version="$1"
    local arch="$2"

    install_terragrunt_binary "$version" "linux" "$arch"
}

install_terragrunt_binary() {
    local version="$1"
    local os="$2"
    local arch="$3"

    # Map OS name for GitHub download URL
    local dl_os="$os"
    if [[ "$os" == "macos" ]]; then
        dl_os="darwin"
    fi

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" RETURN

    local binary_url="https://github.com/gruntwork-io/terragrunt/releases/download/v${version}/terragrunt_${dl_os}_${arch}"
    local binary_path="${tmpdir}/terragrunt"

    log_info "Downloading Terragrunt $version from GitHub releases..."
    if ! download_file "$binary_url" "$binary_path"; then
        log_error "Failed to download Terragrunt"
        return 1
    fi

    chmod +x "$binary_path"

    local install_dir
    install_dir="$(get_install_dir)"
    log_info "Installing to $install_dir..."
    install_binary "$binary_path" "$install_dir" "terragrunt"

    # Verify
    if command_exists terragrunt; then
        log_success "Terragrunt $(get_version terragrunt) installed to $install_dir"
    else
        if [[ "$install_dir" == "$HOME/.local/bin" ]]; then
            log_warn "Terragrunt installed to $install_dir"
            log_warn "Make sure $install_dir is in your PATH:"
            log_warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        fi
    fi
}

# ==============================================================================
# D. Check, Summary & Main
# ==============================================================================

check_tool() {
    local tool="$1"
    local min_version="$2"
    local recommended_version="${3:-}"

    if ! command_exists "$tool"; then
        TOOL_STATUS[$tool]="missing"
        TOOL_VERSION[$tool]=""
        return
    fi

    local version
    version="$(get_version "$tool")"
    TOOL_VERSION[$tool]="$version"

    if [[ -z "$version" ]]; then
        TOOL_STATUS[$tool]="unknown"
        return
    fi

    if ! version_gte "$version" "$min_version"; then
        TOOL_STATUS[$tool]="outdated"
        return
    fi

    if [[ -n "$recommended_version" ]] && ! version_gte "$version" "$recommended_version"; then
        TOOL_STATUS[$tool]="below_recommended"
        return
    fi

    TOOL_STATUS[$tool]="ok"
}

check_all_tools() {
    log_step "Checking installed tools"

    check_tool "terraform" "$MIN_TERRAFORM_VERSION" "$RECOMMENDED_TERRAFORM_VERSION"
    check_tool "terragrunt" "$MIN_TERRAGRUNT_VERSION"
}

print_status_line() {
    local tool="$1"
    local min_version="$2"
    local recommended_version="${3:-}"
    local status="${TOOL_STATUS[$tool]}"
    local version="${TOOL_VERSION[$tool]}"

    case "$status" in
        ok)
            printf "  ${GREEN}✓${RESET} %-14s %s\n" "$tool" "${version}"
            ;;
        below_recommended)
            printf "  ${YELLOW}~${RESET} %-14s %s ${DIM}(recommend >= %s)${RESET}\n" \
                "$tool" "${version}" "$recommended_version"
            ;;
        outdated)
            printf "  ${RED}✗${RESET} %-14s %s ${RED}(need >= %s)${RESET}\n" \
                "$tool" "${version}" "$min_version"
            ;;
        missing)
            printf "  ${RED}✗${RESET} %-14s ${RED}not installed${RESET}\n" "$tool"
            ;;
        unknown)
            printf "  ${YELLOW}?${RESET} %-14s ${YELLOW}installed (version unknown)${RESET}\n" "$tool"
            ;;
    esac
}

print_summary() {
    log_step "Summary"

    print_status_line "terraform" "$MIN_TERRAFORM_VERSION" "$RECOMMENDED_TERRAFORM_VERSION"
    print_status_line "terragrunt" "$MIN_TERRAGRUNT_VERSION"

    echo ""

    # Report errors if any
    if [[ ${#INSTALL_ERRORS[@]} -gt 0 ]]; then
        log_warn "Some installations had issues:"
        for err in "${INSTALL_ERRORS[@]}"; do
            printf "  ${RED}•${RESET} %s\n" "$err"
        done
        echo ""
    fi

    # Check if all tools are OK
    local all_ok=true
    for tool in terraform terragrunt; do
        local status="${TOOL_STATUS[$tool]}"
        if [[ "$status" == "missing" || "$status" == "outdated" ]]; then
            all_ok=false
            break
        fi
    done

    if [[ "$all_ok" == true ]]; then
        log_success "All required tools are installed and meet minimum version requirements."
    else
        log_warn "Some tools need attention. Run './setup.sh' to install missing tools."
    fi
}

needs_install() {
    local tool="$1"
    local status="${TOOL_STATUS[$tool]}"
    [[ "$status" == "missing" || "$status" == "outdated" ]]
}

show_help() {
    cat <<EOF
${BOLD}${SCRIPT_NAME}${RESET} v${SCRIPT_VERSION} - CLI tool setup for unified-terraform-terragrunt plugin

${BOLD}USAGE:${RESET}
    ./${SCRIPT_NAME} [OPTIONS]

${BOLD}OPTIONS:${RESET}
    --check     Check tool status only (no installations)
    --auto      Non-interactive mode (auto-install for CI/CD)
    --help      Show this help message

${BOLD}TOOLS MANAGED:${RESET}
    terraform   >= ${MIN_TERRAFORM_VERSION} (recommended >= ${RECOMMENDED_TERRAFORM_VERSION})
    terragrunt  >= ${MIN_TERRAGRUNT_VERSION}

${BOLD}ENVIRONMENT:${RESET}
    NO_COLOR    Set to disable colored output

${BOLD}EXAMPLES:${RESET}
    ./${SCRIPT_NAME}            # Interactive install
    ./${SCRIPT_NAME} --check    # Check status only
    ./${SCRIPT_NAME} --auto     # CI/CD auto-install
    NO_COLOR=1 ./${SCRIPT_NAME} # No color output
EOF
}

main() {
    printf "${BOLD}Unified Terraform & Terragrunt Plugin - Setup v%s${RESET}\n" "$SCRIPT_VERSION"

    # Detect environment
    local platform arch
    platform="$(detect_platform)"
    arch="$(detect_arch)"
    log_info "Platform: ${platform}/${arch}"

    # Ensure we have a download tool
    ensure_download_tool || exit 1

    # Check all tools
    check_all_tools

    # If check-only, just print summary and exit
    if [[ "$CHECK_ONLY" == true ]]; then
        print_summary
        exit 0
    fi

    # Determine what needs installation
    local tools_to_install=()
    for tool in terraform terragrunt; do
        if needs_install "$tool"; then
            tools_to_install+=("$tool")
        fi
    done

    if [[ ${#tools_to_install[@]} -eq 0 ]]; then
        print_summary
        exit 0
    fi

    # Show what will be installed
    echo ""
    log_info "The following tools need to be installed or updated:"
    for tool in "${tools_to_install[@]}"; do
        local status="${TOOL_STATUS[$tool]}"
        if [[ "$status" == "missing" ]]; then
            printf "  ${YELLOW}•${RESET} %s ${DIM}(not installed)${RESET}\n" "$tool"
        else
            printf "  ${YELLOW}•${RESET} %s ${DIM}(current: %s)${RESET}\n" "$tool" "${TOOL_VERSION[$tool]}"
        fi
    done
    echo ""

    # Confirm
    if ! confirm "Proceed with installation?"; then
        log_info "Installation cancelled."
        exit 0
    fi

    # Install each tool
    for tool in "${tools_to_install[@]}"; do
        if ! "install_${tool}" "$platform" "$arch"; then
            INSTALL_ERRORS+=("$tool: installation failed")
        fi
    done

    # Re-check all tools after installation
    check_all_tools

    # Print final summary
    print_summary

    # Exit with error if anything failed
    if [[ ${#INSTALL_ERRORS[@]} -gt 0 ]]; then
        exit 1
    fi
}

# ==============================================================================
# Argument Parsing
# ==============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)
            CHECK_ONLY=true
            shift
            ;;
        --auto)
            AUTO_MODE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

main
