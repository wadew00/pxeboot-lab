# Headless iPXE provisioning lab

This repository turns a Mac into a small UEFI PXE/iPXE server for an x86-64 bare-metal client such as an HP EliteDesk 800 G1 SFF. It is deliberately controlled from the Mac: the selected installer is stored server-side, so no preboot display is required.

Supported boot targets:

| Target | Remote entry point | Notes |
|---|---|---|
| `local` | none | Safe default; exits PXE and continues the firmware boot order |
| `debian` | `ssh installer@CLIENT_IP` | Debian Installer `network-console`; fully interactive over SSH |
| `ubuntu` | `ssh installer@CLIENT_IP` | Subiquity live installer; SSH key is injected with NoCloud |
| `fedora` | RDP to `CLIENT_IP:3389` | Full remote Anaconda UI; SSH remains available for maintenance |
| `arch` | `ssh root@CLIENT_IP` | Archiso installer shell; run `archinstall` or install manually |
| `alpine` | `ssh root@CLIENT_IP` | Headless live environment; run `setup-alpine` after login |
| `menu` | local keyboard/display | Optional iPXE menu for diagnostics only |

No target in this starter configuration performs an unattended disk write. Debian, Ubuntu, Arch, and Alpine remain operator-driven over SSH; Fedora is operator-driven through an RDP client.

## Network layout

The default configuration matches this lab's shared-router layout:

```text
                         +--- Mac Wi-Fi en0 (192.168.1.106)
Internet --- router -----+
                         +--- HP Ethernet eno1 (a0:48:1c:97:e6:95)
```

`PXE_MODE=proxy` makes dnsmasq a ProxyDHCP server. The router remains the only
server that assigns addresses, gateways, and DNS; the Mac supplies only PXE boot
metadata. Replies are restricted to `PXE_CLIENT_MAC`, so other LAN clients are
ignored. This mode neither assigns an address to `en0` nor enables PF/NAT.

Reserve `PXE_SERVER_IP` for the Mac in the router. The generated boot URLs contain
that address, so `pxeboot doctor` deliberately fails if `en0` no longer owns it.
The current HP address is discovered from the Mac's ARP cache; the router still
owns the actual lease.

The older isolated-cable layout remains available with `PXE_MODE=dedicated`.
That mode needs a separate Ethernet interface, its own DHCP range, and
`PXE_UPLINK_INTERFACE`; `pxeboot` then adds the private address and enables NAT.
Never use `dedicated` mode on a normal LAN that already has DHCP.

## Setup

Requirements: Homebrew `dnsmasq`, `curl`, and `python3`. On this Mac, `dnsmasq` is already installed.

```sh
cp .env.example .env
$EDITOR .env
ln -s "$PWD/pxeboot" /opt/homebrew/bin/pxeboot
pxeboot doctor
```

On the first `up`, `pxeboot` downloads the configured UEFI iPXE chainloader if it is missing. It does not download distro installer payloads to the Mac.

All normal operations go through the globally linked `pxeboot` command. The wrapper resolves its symlink back to this repository, so it works from any directory.

Only the EFI iPXE chainloader is downloaded to the Mac. Debian, Fedora, Arch, and Alpine fetch their boot payloads directly from their official CDN. Ubuntu fetches its kernel, initrd, and live-server ISO directly from Canonical. The vendor URLs are configurable in `.env`.

The small HTTP server is still required for files unique to this lab: the generated
iPXE selector, preseed/kickstart/NoCloud data, and the SSH public key. Large distro
payloads do not pass through or get stored on the Mac.

### Why Ubuntu still needs an ISO

Ubuntu's netboot `linux` and `initrd` only bootstrap the live-server environment. During boot, the initrd downloads the URL passed with `url=`, loop-mounts that ISO, and uses its live filesystem as the Subiquity installer runtime. The ISO is therefore required by Ubuntu's installer design, but it is downloaded by the HP directly from Canonical and is never stored on the Mac.

## Daily use

Start the entire lab and choose the installer in one command:

```sh
pxeboot up debian
```

This renders the generated files and starts HTTP plus dnsmasq in the background.
In the default proxy mode, the Mac's Wi-Fi address and the router configuration are
left untouched. macOS may ask for the administrator password because dnsmasq binds
privileged PXE ports. The target can be `debian`, `ubuntu`, `fedora`, `arch`,
`alpine`, `menu`, or the safe `local` fallback. A target name alone is shorthand,
for example:

```sh
pxeboot fedora
```

Useful commands while it is running:

```sh
pxeboot status
pxeboot leases
pxeboot logs
pxeboot select arch
pxeboot ssh
pxeboot rdp
pxeboot rescue
```

In proxy mode, `leases` and the automatic `ssh`/`rdp` address lookup use the HP's
MAC entry in the Mac ARP cache because the router owns the DHCP lease. You may
always override it with `pxeboot ssh CLIENT_IP` or `pxeboot rdp CLIENT_IP`.
`rescue` starts the headless Arch live environment without launching an installer;
`pxeboot ssh` then connects as root for disk, filesystem, network, and recovery work.

When the lab is finished, stop the managed services and restore the safe local-boot
selection. Proxy mode does not change the Wi-Fi address, router DHCP, or NAT:

```sh
pxeboot down
```

The component scripts under `bin/` remain available for diagnostics, but routine startup and shutdown should use `pxeboot` so service PID and log state stay consistent.

After the machine has fetched the selected target, you can immediately return the server to the safe default without stopping the lab:

```sh
pxeboot select local
```

SSH usernames and entry commands are:

```text
Debian: ssh installer@CLIENT_IP
Ubuntu: ssh installer@CLIENT_IP
Fedora: RDP to CLIENT_IP:3389    full installer UI
        ssh root@CLIENT_IP       maintenance shell
Arch:   ssh root@CLIENT_IP       then run archinstall
Alpine: ssh root@CLIENT_IP       then run setup-alpine
```

### Fedora remote installation

Fedora boots Anaconda with its official RDP remote-install mode. After selecting and booting Fedora, get the client address and temporary credentials:

```sh
pxeboot leases
pxeboot rdp
```

Connect any RDP client to `CLIENT_IP:3389` and complete the normal Anaconda UI remotely. The default `FEDORA_RDP_PASSWORD=auto` generates a random password under the ignored `.run/` directory; it is never committed. `ssh root@CLIENT_IP` remains available with your SSH key for logs and maintenance, but the installation UI is in RDP.

The RDP password is necessarily present in the installer's kernel command line and locally served iPXE script. Treat the provisioning network as trusted and isolated.

## HP EliteDesk firmware settings

This HP already has a local `iPXE UEFI` entry on its EFI System Partition. Use that
entry (or set it once with `efibootmgr --bootnext`) for the first proxy-mode boot.
The local iPXE client gets its address from the router and its script URL from the
Mac. This lab intentionally has no legacy BIOS path. Keep Secure Boot disabled for
the unsigned iPXE binary.

The default `snponly.efi` reuses the HP firmware's UEFI Simple Network Protocol driver and only touches the NIC from which it was chainloaded. If it hangs while initializing or loses the NIC, set `IPXE_EFI_BINARY=ipxe.efi`, rerun `./bin/fetch-assets ipxe`, and then `./bin/render` to use iPXE's native driver instead.

Once installed, either restore disk-first boot order or leave the server target on `local`. The latter makes PXE fall through to the disk without exposing an installer.

## How selection works

In proxy mode the HP can start the iPXE binary already installed on its EFI System
Partition. The router supplies its normal LAN address and the Mac's ProxyDHCP reply
sends `http://SERVER:PORT/boot.ipxe`. Firmware network boot also remains possible:
the Mac can first serve the UEFI chainloader over TFTP. The script chains
`selected.ipxe`, which is atomically changed by `bin/select`. This avoids blind
keyboard timing on a headless machine and avoids the classic iPXE chainloading loop.

## Security and operational notes

- Installer SSH accepts only the public key configured by `SSH_PUBLIC_KEY_FILE`; no private key is copied.
- dnsmasq opens its privileged sockets as root, then drops to the invoking Mac user by default so it can read the project-local TFTP root. `PXE_SERVICE_USER` and `PXE_SERVICE_GROUP` can override this for a dedicated account.
- HTTP and TFTP are intentionally plain text. ProxyDHCP is MAC-restricted, but the
  generated HTTP files still assume the home LAN is trusted.
- `local` is the default and must remain the idle state.
- Verify the client disk before confirming any partitioning screen.
- Distro payloads come directly from vendor HTTPS endpoints on every boot. Their checksums/signatures are not pinned by this lab yet; add verification before treating it as a production provisioning system.

## Troubleshooting

Run `pxeboot doctor` first, then inspect `pxeboot status` and `pxeboot logs`. In
proxy mode, the router/AP must bridge PXE broadcasts between wired Ethernet and
Wi-Fi; disable wireless/client isolation if it blocks them. If firmware gets an
address but never loads iPXE, check UDP 69 and the TFTP root. If iPXE loads but never
gets `boot.ipxe`, check UDP 4011 and the dnsmasq log. If the installer boots but SSH
is unreachable, use `pxeboot leases`, then check the public key and macOS firewall.
