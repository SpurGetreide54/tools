# SSH Relay Manager

SSH Relay Manager is a Windows tool. It manages SSH relay rules on a Hyper-V host.

A relay rule forwards an IPv4 connection on the host to an IPv6 address, usually a VM. Use this tool when you have IPv4-only access, but your VMs only have IPv6 addresses.

The tool does not connect to a VM. It only manages the relay rules. You run the actual `ssh` command yourself.

See [docs/relay-concept.md](docs/relay-concept.md) for a deeper explanation of how the relay works.

## Requirements

- Windows with Hyper-V.
- Windows PowerShell 5.1 (Desktop edition). Run `$PSVersionTable` to check your version.
- Administrator rights. The tool refuses to start without them.

## Setup

1. Copy `SshRelayManager.ps1` to a folder on the host, for example `C:\Tools\ssh-relay-manager\`.
2. Create a desktop shortcut. Set its target to:
   ```
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Tools\ssh-relay-manager\SshRelayManager.ps1"
   ```
3. Open the shortcut's properties. Open the Advanced settings. Check "Run as administrator".

From now on, double-click the shortcut to start the tool as Administrator.

## Usage

- **Add Rule**: Enter a name, the VM's IPv6 address, and the ports. Click "Add Rule". The tool creates the relay rule and a matching firewall rule.
- **Edit Selected**: Select a rule in the list. Click "Edit Selected" to load it into the form, change any field (name, IPv6 address, ports), then click "Save Changes". The tool recreates the relay rule and its firewall rule under the new settings, so the port is briefly unavailable during the save.
- **Clear**: Resets the form.
- **Delete Selected**: Select a rule in the list. Click "Delete Selected". The tool removes the relay rule and its firewall rule.
- **Refresh**: Reloads the rule list. The tool also checks the rule list against the live system state on every refresh, so external changes still show up.

After you add a rule, connect from your IPv4-only machine with:
```
ssh -p <listen-port> <vm-user>@<host-public-ipv4>
```

The tool stores its rules in `rules.json`, next to the script.
