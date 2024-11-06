#!/bin/bash

# Script Name: cloudpanel-mysql-backup.sh
# Description: Backup MySQL databases using CloudPanel's export tool and optionally sync backups to a remote server using rsync. Includes rotation of old backups and optional remote deletion.
# Author: Rojen Zaman
# Date: 2024

# Variables
BACKUP_DIR=""
DATABASE_NAME=""
RSYNC_TARGET_DIR=""
REMOTE_HOST=""
CONFIG_FILE=""
LOG_FILE=""
ENABLE_RSYNC=false
RETENTION_DAYS=0  # Default to 0 (no deletion)
RSYNC_DELETE=false  # Default to false (do not delete files on remote)

# Functions
usage() {
    cat << EOF
Usage: $0 [options]

Options:
  -b, --backup-dir DIR       Specify the backup directory.
  -d, --database-name NAME   Specify the database name to export.
  -r, --rsync-target-dir DIR Specify the remote rsync target directory.
  -h, --remote-host HOST     Specify the remote host (configured in ~/.ssh/config).
  -c, --config-file FILE     Specify the path to database.conf file.
  --enable-rsync             Enable rsync synchronization after backup.
  --rsync-delete             Enable deletion of files on the remote server during rsync.
  --retention-days DAYS      Specify the number of days to keep backups. Older backups will be deleted.
  -?, --help                 Display this help message.

Description:
  This script exports a MySQL database using CloudPanel's export tool and optionally synchronizes
  the backups to a remote server using rsync. It also supports rotation of old backups based on
  a specified number of days. Optionally, it can delete old backups on the remote server during rsync.

Notes:
  - The backup directory will have a hierarchical structure: BACKUP_DIR/YEAR/MONTH/DAY.
  - The dump file will include the database name and a timestamp in its filename.
  - The script requires 'clpctl' and 'rsync' commands to be available.
  - SSH must be configured with public key authentication and the remote host must be defined in ~/.ssh/config.
  - If the database export fails, synchronization will not occur.
  - The backup log is stored at BACKUP_DIR/backup.log.
  - To use a configuration file for database settings, specify it with the --config-file option.

Configuration File:
  - The configuration file should be in 'key=value' format.
  - Available options in the configuration file:
    DATABASE_NAME
    BACKUP_DIR
    RSYNC_TARGET_DIR
    REMOTE_HOST
    ENABLE_RSYNC (true/false)
    RSYNC_DELETE (true/false)
    RETENTION_DAYS

  - Command-line arguments override configuration file settings.

RSYNC:
  - To enable rsync synchronization, use the --enable-rsync option.
  - Use the --rsync-delete option to delete files on the remote server that have been deleted locally.
  - Ensure SSH is configured with public key authentication.
  - The remote host must be defined in ~/.ssh/config.
  - Example SSH config for the remote host:

    Host remote_host
        HostName example.com
        User username
        IdentityFile ~/.ssh/id_rsa

  - The script will synchronize the backup directory to the remote target directory while preserving the directory structure.

Backup Rotation:
  - Use the --retention-days option to specify how many days of backups to keep.
  - Backups older than the specified number of days will be deleted locally.
  - Empty directories (day/month/year) left after deletion will also be removed.

EOF
}

# Parse initial arguments to get --config-file
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -c|--config-file)
        CONFIG_FILE="$2"
        shift; shift
        ;;
        -\?|--help)
        usage
        exit 0
        ;;
        *)
        shift
        ;;
    esac
done

# Read config file if specified
if [[ -n "$CONFIG_FILE" ]]; then
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        echo "Error: Config file '$CONFIG_FILE' not found."
        exit 1
    fi
fi

# Reset argument pointer
set -- "${@}"

# Parse arguments again
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -b|--backup-dir)
        BACKUP_DIR="$2"
        shift; shift
        ;;
        -d|--database-name)
        DATABASE_NAME="$2"
        shift; shift
        ;;
        -r|--rsync-target-dir)
        RSYNC_TARGET_DIR="$2"
        shift; shift
        ;;
        -h|--remote-host)
        REMOTE_HOST="$2"
        shift; shift
        ;;
        --enable-rsync)
        ENABLE_RSYNC=true
        shift
        ;;
        --rsync-delete)
        RSYNC_DELETE=true
        shift
        ;;
        --retention-days)
        RETENTION_DAYS="$2"
        shift; shift
        ;;
        -\?|--help)
        usage
        exit 0
        ;;
        *)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
done

# Check required arguments
if [[ -z "$BACKUP_DIR" ]]; then
    echo "Error: Backup directory is required."
    usage
    exit 1
fi

if [[ -z "$DATABASE_NAME" ]]; then
    echo "Error: Database name is required."
    usage
    exit 1
fi

# Set LOG_FILE
LOG_FILE="$BACKUP_DIR/backup.log"

# Create backup directory if it doesn't exist
if [[ ! -d "$BACKUP_DIR" ]]; then
    mkdir -p "$BACKUP_DIR"
fi

# Function to log messages
log_message() {
    local MESSAGE="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $MESSAGE" | tee -a "$LOG_FILE"
}

# Check for required commands
if ! command -v clpctl &> /dev/null; then
    log_message "Error: 'clpctl' command not found."
    exit 1
fi

if $ENABLE_RSYNC && ! command -v rsync &> /dev/null; then
    log_message "Error: 'rsync' command not found."
    exit 1
fi

# Check SSH configuration for rsync if enabled
if $ENABLE_RSYNC; then
    if [[ -z "$RSYNC_TARGET_DIR" ]] || [[ -z "$REMOTE_HOST" ]]; then
        log_message "Error: RSYNC_TARGET_DIR and REMOTE_HOST must be specified when rsync is enabled."
        exit 1
    fi
    # Check if SSH config is set up
    if ! grep -qi "^[[:space:]]*Host[[:space:]]\+$REMOTE_HOST\b" ~/.ssh/config; then
        log_message "Error: SSH config for host '$REMOTE_HOST' not found in ~/.ssh/config."
        exit 1
    fi
fi

# Construct backup directory hierarchy
YEAR=$(date '+%Y')
MONTH=$(date '+%m')
DAY=$(date '+%d')

DEST_DIR="$BACKUP_DIR/$YEAR/$MONTH/$DAY"
mkdir -p "$DEST_DIR"

# Create timestamp for filename
TIMESTAMP=$(date '+%Y-%m-%d-%H-%M-%S')

# Set dump file name
DUMP_FILE="$DEST_DIR/${DATABASE_NAME}_${TIMESTAMP}.sql.gz"

# Export database
log_message "Starting database export for '$DATABASE_NAME'."
if clpctl db:export --databaseName="$DATABASE_NAME" --file="$DUMP_FILE"; then
    log_message "Database export completed successfully. Dump file: $DUMP_FILE"
else
    log_message "Error: Database export failed."
    exit 1
fi

# Backup Rotation
if [[ "$RETENTION_DAYS" -gt 0 ]]; then
    log_message "Starting backup rotation. Retaining backups from the last $RETENTION_DAYS day(s)."
    find "$BACKUP_DIR" -type f -name "*.sql.gz" -mtime +"$RETENTION_DAYS" -exec rm -f {} \;

    # Remove empty directories (day/month/year)
    find "$BACKUP_DIR" -type d -empty -delete

    log_message "Backup rotation completed. Old backups deleted."
fi

# Perform rsync if enabled
if $ENABLE_RSYNC; then
    log_message "Starting rsync synchronization to '$REMOTE_HOST:$RSYNC_TARGET_DIR'."
    RSYNC_OPTIONS="-avz"
    if $RSYNC_DELETE; then
        RSYNC_OPTIONS="$RSYNC_OPTIONS --delete"
        log_message "Rsync will delete files on remote server that no longer exist locally."
    fi
    if rsync $RSYNC_OPTIONS "$BACKUP_DIR/" "$REMOTE_HOST:$RSYNC_TARGET_DIR"; then
        log_message "Rsync synchronization completed successfully."
    else
        log_message "Error: Rsync synchronization failed."
        exit 1
    fi
fi

log_message "Backup script completed successfully."
exit 0
