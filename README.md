# esx-health

A small Bash wrapper that queries an ESXi host using PowerShell PowerCLI and lists all current VM snapshots.

## Features

- Connects to an ESXi host or vCenter server
- Uses `VCF.PowerCLI` / `VCF.VimAutomation.Core` or `VMware.PowerCLI` fallback
- Supports stored credentials in a local config file
- Suppresses PowerCLI startup banner and deprecation warnings where possible

## Requirements

- `bash`
- `pwsh` (PowerShell Core)
- VMware PowerCLI or VCF PowerCLI modules installed

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
- `--list-vms`         List all VMs and their current power state instead of snapshots
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

To list all virtual machines and whether they are powered on or off, use PowerCLI directly with a simple command:

```powershell
Get-VM | Select-Object Name, PowerState | Format-Table -AutoSize
```

This returns a table with each VM name and its current power state (`PoweredOn`, `PoweredOff`, or `Suspended`).

## Notes

- The credential config file is excluded from Git through `.gitignore`.
- If no username or password is supplied, the script prompts interactively.
