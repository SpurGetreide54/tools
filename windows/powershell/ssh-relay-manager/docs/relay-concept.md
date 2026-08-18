# How the relay works

This document explains the relay mechanism behind SSH Relay Manager.

## The problem

Your VM has a public IPv6 address. Your client machine has an IPv4 address only. IPv4-only machines cannot reach IPv6-only addresses directly.

One fix is to add an SSH server on the Hyper-V host. You connect to the host first, then jump to the VM. This fix works, but it adds a new, authenticating SSH server to the host. That server is a new attack target.

## The relay fix

Windows includes a built-in command, `netsh interface portproxy`. This command relays TCP connections from one address and port to another address and port.

SSH Relay Manager uses `portproxy` in `v4tov6` mode. It relays a connection from the host's IPv4 address to a VM's IPv6 address.

The relay works at the transport layer. It does not read or check the traffic. It does not authenticate the connection. Your SSH client still authenticates directly against the VM's SSH server, with your normal key. The host never sees your credentials and never grants a shell.

This is safer than an SSH server on the host. The host forwards bytes. It does not log you in.

## Elevation

`netsh portproxy` and Windows Firewall rules both need Administrator rights. SSH Relay Manager checks for these rights on startup. It shows an error and exits if you did not start it as Administrator.

The tool does not attempt to elevate itself. You must start it as Administrator yourself, for example through a shortcut with "Run as administrator" set.

## Firewall rules

A relay rule alone does not open the host's firewall. SSH Relay Manager creates one matching inbound firewall rule for each relay rule, named `SSHRelay-<name>`. When you delete a relay rule, the tool also removes its firewall rule.

The firewall rule allows connections from any source address. This avoids lockouts if your own IPv4 address changes, which is common on home internet connections.

## Reconciliation

SSH Relay Manager stores its rules in `rules.json`, next to the script. This file only holds names and metadata. The real rules live in Windows itself.

On every start and on every refresh, the tool compares `rules.json` against the live `netsh` rule list:

- A live rule with no matching entry in `rules.json` gets added to `rules.json`, under the name `Imported-<port>`. This covers rules you created manually, outside the tool.
- An entry in `rules.json` with no matching live rule gets removed from `rules.json`. This covers rules removed outside the tool.

This step keeps the tool's rule list, and its port suggestions, in sync with the real system state.
