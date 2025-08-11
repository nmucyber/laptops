#!/bin/bash

# Script to update hostname and /etc/hosts file
# Requires root privileges to modify system files

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to validate hostname format
validate_hostname() {
    local hostname="$1"
    
    # Check if hostname is empty
    if [[ -z "$hostname" ]]; then
        print_error "Hostname cannot be empty"
        return 1
    fi
    
    # Check hostname length (max 253 characters)
    if [[ ${#hostname} -gt 253 ]]; then
        print_error "Hostname too long (max 253 characters)"
        return 1
    fi
    
    # Check if hostname contains valid characters (letters, numbers, hyphens, dots)
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        print_error "Hostname contains invalid characters. Use only letters, numbers, hyphens, and dots"
        return 1
    fi
    
    # Check if hostname starts or ends with hyphen
    if [[ "$hostname" =~ ^- ]] || [[ "$hostname" =~ -$ ]]; then
        print_error "Hostname cannot start or end with a hyphen"
        return 1
    fi
    
    return 0
}

# Function to backup /etc/hosts
backup_hosts() {
    local backup_file="/etc/hosts.backup.$(date +%Y%m%d_%H%M%S)"
    cp /etc/hosts "$backup_file" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        print_success "Backup created: $backup_file"
        echo "$backup_file"
    else
        print_error "Failed to create backup of /etc/hosts"
        return 1
    fi
}

# Function to update hostname
update_hostname() {
    local new_hostname="$1"
    local old_hostname
    
    # Get current hostname
    old_hostname=$(hostname)
    print_status "Current hostname: $old_hostname"
    print_status "Setting new hostname to: $new_hostname"
    
    # Update hostname using hostnamectl (systemd systems)
    if command -v hostnamectl >/dev/null 2>&1; then
        hostnamectl set-hostname "$new_hostname"
        if [[ $? -eq 0 ]]; then
            print_success "Hostname updated using hostnamectl"
        else
            print_error "Failed to update hostname using hostnamectl"
            return 1
        fi
    else
        # Fallback: Update hostname file directly
        echo "$new_hostname" > /etc/hostname
        if [[ $? -eq 0 ]]; then
            print_success "Hostname file updated"
            # Set hostname for current session
            hostname "$new_hostname"
        else
            print_error "Failed to update /etc/hostname"
            return 1
        fi
    fi
    
    echo "$old_hostname"
}

# Function to update /etc/hosts file
update_hosts_file() {
    local new_hostname="$1"
    local old_hostname="$2"
    local backup_file="$3"
    
    print_status "Updating /etc/hosts file"
    
    # Create temporary file
    local temp_file=$(mktemp)
    
    # Read /etc/hosts and update entries
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            echo "$line" >> "$temp_file"
            continue
        fi
        
        # Check if line contains old hostname
        if [[ "$line" =~ [[:space:]]"$old_hostname"([[:space:]]|$) ]]; then
            # Replace old hostname with new hostname
            updated_line=$(echo "$line" | sed "s/\b$old_hostname\b/$new_hostname/g")
            echo "$updated_line" >> "$temp_file"
            print_status "Updated line: $updated_line"
        else
            echo "$line" >> "$temp_file"
        fi
    done < /etc/hosts
    
    # Check if localhost entries exist, add if missing
    if ! grep -q "127.0.0.1.*$new_hostname" "$temp_file"; then
        print_status "Adding localhost entry for new hostname"
        # Add after existing 127.0.0.1 line or at the beginning
        if grep -q "^127.0.0.1" "$temp_file"; then
            sed -i "/^127.0.0.1.*localhost/s/$/ $new_hostname/" "$temp_file"
        else
            sed -i "1i127.0.0.1 localhost $new_hostname" "$temp_file"
        fi
    fi
    
    # Replace /etc/hosts with updated content
    cp "$temp_file" /etc/hosts
    if [[ $? -eq 0 ]]; then
        print_success "/etc/hosts file updated successfully"
        rm "$temp_file"
    else
        print_error "Failed to update /etc/hosts"
        print_warning "Restoring backup from $backup_file"
        cp "$backup_file" /etc/hosts
        rm "$temp_file"
        return 1
    fi
}

# Main function
main() {
    print_status "Hostname Update Script"
    print_status "======================"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Get input from user
    echo
    read -p "Enter the new hostname: " new_hostname
    
    # Validate hostname
    if ! validate_hostname "$new_hostname"; then
        exit 1
    fi
    
    # Get current hostname
    current_hostname=$(hostname)
    
    # Check if hostname is already set
    if [[ "$new_hostname" == "$current_hostname" ]]; then
        print_warning "Hostname is already set to '$new_hostname'"
        read -p "Do you want to continue anyway? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_status "Operation cancelled"
            exit 0
        fi
    fi
    
    # Confirm changes
    echo
    print_status "Current hostname: $current_hostname"
    print_status "New hostname: $new_hostname"
    echo
    read -p "Do you want to proceed with these changes? (y/N): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_status "Operation cancelled"
        exit 0
    fi
    
    echo
    print_status "Starting hostname update process..."
    
    # Create backup of /etc/hosts
    backup_file=$(backup_hosts)
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
    
    # Update hostname
    old_hostname=$(update_hostname "$new_hostname")
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
    
    # Update /etc/hosts file
    update_hosts_file "$new_hostname" "$old_hostname" "$backup_file"
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
    
    echo
    print_success "Hostname update completed successfully!"
    print_status "New hostname: $(hostname)"
    print_warning "Note: You may need to restart your terminal or log out/in for all changes to take effect"
    print_warning "Some applications may require a system reboot to recognize the new hostname"
}

# Run main function
main "$@"