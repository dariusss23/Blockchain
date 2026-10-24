# Prerequisites

This lab uses [Foundry](https://getfoundry.sh/), a toolkit for Ethereum development. The instructions below are for **Linux**.

> **Windows users:** Foundry must be installed and run inside **WSL** (Windows Subsystem for Linux). To install WSL, open PowerShell as Administrator and run `wsl --install`. Restart the computer, then run all the commands below in the WSL (Ubuntu) terminal.

## Installing Foundry

1. Install `foundryup`, the Foundry installer:

   ```bash
   curl -L https://getfoundry.sh/install | bash
   ```

2. Reload your shell so that `foundryup` is on your `PATH`:

   ```bash
   source ~/.bashrc
   ```

3. Install the Foundry tools (`forge`, `cast`, `anvil`, `chisel`):

   ```bash
   foundryup
   ```

## Verifying the installation

Check that each tool is installed by printing its version:

```bash
forge --version
cast --version
anvil --version
chisel --version
```

Each command should print a version number. If you get `command not found`, open a new terminal or run `source ~/.bashrc`, then try again.

