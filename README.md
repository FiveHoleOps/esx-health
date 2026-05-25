# esx-health

A small Bash wrapper that queries an ESXi host using SSH and lists all current VM snapshots.

## Features

- Connects directly to an ESXi host via SSH
- Bypasses read-only API restrictions in ESXi Free Edition for real-time datastore metrics
- Supports stored credentials in a local config file

## Requirements

- `bash`
- `ssh`
- `sshpass` (for automated password authentication)

## Usage

```bash
./esxhealth
```

Options:

- `-h, --host`         ESXi host or vCenter server
- `-u, --user`         ESXi username
- `-p, --password`     ESXi password
- `--save-creds`       Save credentials to the default config file
- `--config-file file` Use a custom credential file
- `-list`              List all VMs and their current power state
- `-snaps`             List all current snapshots
- `-ds`                List datastores and their free space
- `-uptime`            Show the ESXi host uptime
- `--help`             Show usage information

### Environment variables

You can also set credentials through environment variables:

- `ESX_HOST`
- `ESX_USER`
- `ESX_PASSWORD`
- `ESXHEALTH_CONFIG`

## Config file

By default, the script uses a local config file at `.esxhealth.conf`.

Example config format:

```text
ESX_HOST=192.168.3.7
ESX_USER=root
ESX_PASSWORD="secret"
```

## Example

```bash
./esxhealth --host 192.168.3.7 --user root --password secret --save-creds
```

## List all VMs and power state

To list all virtual machines and whether they are powered on or off, the script natively parses `vim-cmd` over SSH:

```bash
vim-cmd vmsvc/getallvms
```

This returns a table with each VM name and its current power state (`PoweredOn`, `PoweredOff`, or `Suspended`).

## Notes

- The credential config file is excluded from Git through `.gitignore`.
- If no username or password is supplied, the script prompts interactively.
