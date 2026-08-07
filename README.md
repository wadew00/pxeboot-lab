# Headless iPXE provisioning lab

This repository turns a Mac into a small UEFI PXE/iPXE server for an x86-64 bare-metal client such as an HP EliteDesk 800 G1 SFF. It is deliberately controlled from the Mac: the selected installer is stored server-side, so no preboot display is required.

Supported boot targets:

| Target | Remote entry point | Notes |
|---|---|---|
| `local` | none | Safe default; exits PXE and continues the firmware boot order |
| `debian` | `ssh installer@CLIENT_IP` | Debian Installer `network-console`; fully interactive over SSH |
| `ubuntu` | `ssh installer@CLIENT_IP` | Subiquity live installer; SSH key is injected with NoCloud |
| `fedora` | `ssh root@CLIENT_IP` | Anaconda maintenance/monitoring shell; see Fedora limitation below |
| `arch` | `ssh root@CLIENT_IP` | Archiso installer shell; run `archinstall` or install manually |
| `alpine` | `ssh root@CLIENT_IP` | Headless live environment; run `setup-alpine` after login |
| `menu` | local keyboard/display | Optional iPXE menu for diagnostics only |

No target in this starter configuration performs an unattended disk write. Debian, Ubuntu, Arch, and Alpine remain operator-driven over SSH; Fedora provides SSH maintenance access but needs a separate reviewed Kickstart for headless installation.

## Network layout

Use a dedicated USB Ethernet adapter or isolated VLAN. The examples assume:

```text
Internet/Wi-Fi --- Mac
                  192.168.50.1/24 (dedicated Ethernet)
                         |
                         +--- HP EliteDesk (PXE boot)
```

Do not run this DHCP service on a normal LAN that already has DHCP. The installer needs internet access to fetch vendor-hosted boot payloads and packages. `bin/nat-up` provides this through the Mac's uplink using an isolated PF anchor. macOS Internet Sharing normally starts its own DHCP service and therefore must not be enabled on the same interface as this `dnsmasq` instance.

## Setup

Requirements: Homebrew `dnsmasq`, `curl`, and `python3`. On this Mac, `dnsmasq` is already installed.

```sh
cp .env.example .env
$EDITOR .env
./bin/doctor
./bin/fetch-assets ipxe
./bin/render
```

Only the EFI iPXE chainloader is downloaded to the Mac. Debian, Fedora, Arch, and Alpine fetch their boot payloads directly from their official CDN. Ubuntu fetches its kernel, initrd, and live-server ISO directly from Canonical. The vendor URLs are configurable in `.env`.

### Why Ubuntu still needs an ISO

Ubuntu's netboot `linux` and `initrd` only bootstrap the live-server environment. During boot, the initrd downloads the URL passed with `url=`, loop-mounts that ISO, and uses its live filesystem as the Subiquity installer runtime. The ISO is therefore required by Ubuntu's installer design, but it is downloaded by the HP directly from Canonical and is never stored on the Mac.

Assign the `.env` address to the `.env` interface, then enable NAT (these change host networking and need administrator privileges):

```sh
./bin/interface-up
./bin/nat-up
```

Start both servers:

```sh
./bin/serve
```

When the lab is finished, stop `bin/serve` with Ctrl-C and clear only this lab's NAT anchor:

```sh
./bin/nat-down
./bin/interface-down
```

Then choose the next boot from a second terminal and power-cycle/PXE-boot the HP:

```sh
./bin/select debian
./bin/leases
ssh installer@192.168.50.100
```

After the machine has fetched the selected target, immediately return the server to the safe default:

```sh
./bin/select local
```

`./bin/leases` prints the address assigned by `dnsmasq`. SSH usernames and entry commands are:

```text
Debian: ssh installer@CLIENT_IP
Ubuntu: ssh installer@CLIENT_IP
Fedora: ssh root@CLIENT_IP
Arch:   ssh root@CLIENT_IP       then run archinstall
Alpine: ssh root@CLIENT_IP       then run setup-alpine
```

### Fedora limitation

Anaconda's `inst.sshd` mode officially exposes SSH for monitoring and debugging; it does not transport the current installer UI over SSH. The included partial Kickstart authorizes the temporary root account but deliberately contains no disk or installation commands. A truly headless Fedora installation therefore needs either a reviewed full Kickstart profile or Anaconda's remote graphical mode. Do not mistake the Fedora SSH shell for an interactive Anaconda TUI.

## HP EliteDesk firmware settings

Enable UEFI network boot over IPv4 and place it ahead of the target disk for the initial boot. This lab intentionally has no legacy BIOS path. Disable Secure Boot for the unsigned upstream iPXE binary.

The default `snponly.efi` reuses the HP firmware's UEFI Simple Network Protocol driver and only touches the NIC from which it was chainloaded. If it hangs while initializing or loses the NIC, set `IPXE_EFI_BINARY=ipxe.efi`, rerun `./bin/fetch-assets ipxe`, and then `./bin/render` to use iPXE's native driver instead.

Once installed, either restore disk-first boot order or leave the server target on `local`. The latter makes PXE fall through to the disk without exposing an installer.

## How selection works

The UEFI firmware downloads iPXE over TFTP. The second DHCP exchange identifies iPXE and sends it `http://SERVER:PORT/boot.ipxe`. That script chains `selected.ipxe`, which is atomically changed by `bin/select`. This avoids blind keyboard timing on a headless machine and avoids the classic PXE-to-iPXE chainloading loop.

## Security and operational notes

- Installer SSH accepts only the public key configured by `SSH_PUBLIC_KEY_FILE`; no private key is copied.
- The HTTP and TFTP services are intentionally plain text and belong only on an isolated provisioning network.
- `local` is the default and must remain the idle state.
- Verify the client disk before confirming any partitioning screen.
- Distro payloads come directly from vendor HTTPS endpoints on every boot. Their checksums/signatures are not pinned by this lab yet; add verification before treating it as a production provisioning system.

## Troubleshooting

Run `./bin/doctor` first. If the firmware gets an address but never loads iPXE, check UDP 69 and the TFTP root. If iPXE loads repeatedly, the DHCP option-175 match is not being seen. If the installer boots but SSH is unreachable, use `./bin/leases`, then check that the selected distro received the public key and that the lab network is not being filtered by the macOS firewall.
