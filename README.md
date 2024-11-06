# CloudPanel MySQL Backup Script

A Bash script to automate MySQL database backups on CloudPanel. This script exports databases, organizes backups in a structured directory, and can sync backups to a remote server via `rsync`. Designed for production use, the script supports backup rotation and remote cleanup options.

## Features

- **MySQL Database Export**: Uses CloudPanel's `clpctl` tool to export databases.
- **Organized Backup Structure**: Stores backups hierarchically by `YEAR/MONTH/DAY` directories.
- **Configurable Backup Retention**: Removes backups older than a specified number of days.
- **Remote Sync with Rsync**: Optionally syncs backups to a remote server using `rsync`.
- **Remote Cleanup Option**: Deletes old backups from the remote server if desired.
- **Detailed Logging**: Logs all operations to `backup.log`.

## Requirements

- CloudPanel with `clpctl` installed
- `rsync` (for remote sync)
- SSH access with public key authentication for remote server sync

## Usage

### Basic Command

```bash
./cloudpanel-mysql-backup.sh --backup-dir /path/to/backup --database-name my_database
````

### With Remote Sync and Retention

```bash
./cloudpanel-mysql-backup.sh \
  --backup-dir /path/to/backup \
  --database-name my_database \
  --enable-rsync \
  --rsync-target-dir /remote/backup/path \
  --remote-host remote_host \
  --retention-days 7 \
  --rsync-delete
```

### Configuration File

Alternatively, you can specify options in a configuration file:

```bash
./cloudpanel-mysql-backup.sh --config-file /path/to/config.conf
```

Sample `config.conf` file:

```ini
DATABASE_NAME=my_database
BACKUP_DIR=/path/to/backup
ENABLE_RSYNC=true
RSYNC_TARGET_DIR=/remote/backup/path
REMOTE_HOST=remote_host
RETENTION_DAYS=7
RSYNC_DELETE=true
```

### Example Crontab

Run the backup every hour at the 15th and 45th minute:

```cron
15,45 * * * * /path/to/cloudpanel-mysql-backup.sh --config-file /path/to/config.conf >> /path/to/logs/backup.log 2>&1
```

## Options

- `--backup-dir DIR`          : Specify the local backup directory.
- `--database-name NAME`       : Specify the database to export.
- `--enable-rsync`             : Enable rsync to sync backups to a remote server.
- `--rsync-target-dir DIR`     : Set the target directory on the remote server.
- `--remote-host HOST`         : Set the remote server hostname (defined in `~/.ssh/config`).
- `--retention-days DAYS`      : Specify days to keep backups; older backups are deleted.
- `--rsync-delete`             : Delete files on the remote server that are deleted locally.
- `--config-file FILE`         : Load options from a configuration file.
- `--help`                     : Display usage information.

## License

MIT License
