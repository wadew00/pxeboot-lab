# Headless iPXE provisioning lab

This repository turns a Mac into a small UEFI PXE/iPXE server for an x86-64 bare-metal client such as an HP EliteDesk 800 G1 SFF. Selection and control files live on the Mac; installer payloads come directly from distro servers, so no preboot display is required.

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

## Topology profiles

Network topology changes only how the HP gets an address and discovers
`boot.ipxe`. Once HTTP chaining starts, every distro target follows the same path.
There is intentionally no universal "guess and start DHCP" mode; authoritative
DHCP on the wrong interface can disrupt a normal LAN.

| Profile | Address/discovery | Mac services | Use when |
|---|---|---|---|
| `shared-router` | Router DHCP + Mac ProxyDHCP | HTTP, ProxyDHCP, optional TFTP | Mac and HP share one broadcast domain |
| `direct-cable` | Mac authoritative DHCP | HTTP, DHCP/TFTP, PF NAT | HP is on an isolated cable/switch/VLAN |
| `esp-http` | Router DHCP + ESP `autoexec.ipxe` | HTTP only | HP can route to a stable Mac IP/DNS name |

The default `shared-router` profile matches this lab:

```text
                         +--- Mac Wi-Fi en0 (192.168.1.106)
Internet --- router -----+
                         +--- HP Ethernet eno1 (a0:48:1c:97:e6:95)
```

The router remains the only
server that assigns addresses, gateways, and DNS; the Mac supplies only PXE boot
metadata. Replies are restricted to `PXE_CLIENT_MAC`, so other LAN clients are
ignored. This mode neither assigns an address to `en0` nor enables PF/NAT.

With `PXE_INTERFACE`, `PXE_SERVER_IP`, `PXE_SUBNET`, and `PXE_NETMASK` set to
`auto`, `pxeboot` resolves the HP's ARP interface first and falls back to the
default-route interface. It calculates the real CIDR rather than assuming `/24`.
Automatic selection never enables authoritative DHCP or NAT.

`direct-cable` requires an explicit isolated `PXE_INTERFACE`; `auto` is rejected.
It also refuses an interface that already has a normal LAN address, equals the
uplink, or overlaps the uplink subnet. Never use this profile on a LAN that already
has DHCP.

`esp-http` removes broadcast discovery entirely. It works across routed networks
when routing, DNS, and firewalls allow the HP to reach `PXE_BOOT_URL`. It requires
a stable router reservation/IP or real unicast DNS record such as
`pxeboot.home.arpa`; do not assume that Bonjour `.local` names work in iPXE.
ProxyDHCP cannot cross a VLAN/router boundary without a DHCP relay, and guest/client
isolation can block it even when addresses look similar.

Inspect or change profiles with:

```sh
pxeboot profile list
pxeboot profile detect
pxeboot topology
pxeboot profile use shared-router
pxeboot profile use direct-cable en5
pxeboot profile use esp-http http://pxeboot.home.arpa:8080
```

## Setup

Requirements: `curl`, `python3`, and Homebrew `dnsmasq` for `shared-router` or
`direct-cable`. The `esp-http` profile does not run dnsmasq.

```sh
cp .env.example .env
$EDITOR .env
sudo ln -sf "$PWD/pxeboot" "$(brew --prefix)/bin/pxeboot"
pxeboot doctor
pxeboot topology
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

This resolves the selected topology, freezes the effective values in the ignored
`.run/session.env`, renders the generated files, and starts the profile's services.
Changing Wi-Fi, `.env`, or profiles during a session cannot make `down` clean the
wrong interface; restart the session to apply a changed address. In
`shared-router`, the Mac's Wi-Fi address and router configuration are untouched.
macOS may ask for the administrator password when dnsmasq binds privileged ports.
The target can be `debian`, `ubuntu`, `fedora`, `arch`, `alpine`, `menu`, or the
safe `local` fallback. A target name alone is shorthand, for example:

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
pxeboot topology
```

In router-managed profiles, `leases` and the automatic `ssh`/`rdp` address lookup use the HP's
MAC entry in the Mac ARP cache because the router owns the DHCP lease. You may
always override it with `pxeboot ssh CLIENT_IP` or `pxeboot rdp CLIENT_IP`.
`rescue` starts the headless Arch live environment without launching an installer;
`pxeboot ssh` then connects as root for disk, filesystem, network, and recovery work.

When the lab is finished, stop the managed services and restore the safe local-boot
selection. Router-managed profiles do not change the Wi-Fi address, router DHCP,
or NAT:

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

This HP already has a local `iPXE UEFI` entry (`Boot0007`) on its EFI System
Partition. It points to Debian's full `ipxe-amd64.efi`, which is correct for a disk
ESP launch. Use it for one boot with:

```sh
sudo efibootmgr -n 0007
sudo reboot
```

This lab intentionally has no legacy BIOS path. Keep Secure Boot disabled for the
unsigned iPXE binary.

`IPXE_EFI_BINARY=snponly.efi` applies only when firmware network boot downloads a
first stage over TFTP. It reuses firmware networking and is not the persistent ESP
binary. Change that setting to `ipxe.efi` only if TFTP-chainloaded `snponly.efi`
has trouble with the HP NIC.

### Persistent ESP HTTP bootstrap

The installed full iPXE automatically reads `/boot/efi/autoexec.ipxe`. First set
a stable URL; then generate the script. It runs DHCP, prefers a current
ProxyDHCP URL when available, falls back to that stable URL, and returns to UEFI
on failure:

```sh
pxeboot down
pxeboot profile use esp-http http://192.168.1.106:8080
pxeboot bootstrap
pxeboot up local
```

While Debian is still running on the HP, install the served copy (use the URL
printed by `pxeboot bootstrap`):

```sh
curl -fsS http://192.168.1.106:8080/autoexec.ipxe -o /tmp/autoexec.ipxe
sudo install -m 0644 /tmp/autoexec.ipxe /boot/efi/autoexec.ipxe
rm /tmp/autoexec.ipxe
```

After this enrollment, `esp-http` needs only the Mac HTTP server. To boot rescue:

```sh
pxeboot doctor
pxeboot rescue
```

Regenerate and reinstall `autoexec.ipxe` whenever its stable URL changes. Across
routed networks, pass the client address to `pxeboot ssh CLIENT_IP` or set
`PXE_CLIENT_IP`; ARP discovery only works on the local LAN.

If an installer reformats the EFI System Partition, reinstall both the full iPXE
binary/UEFI entry and `autoexec.ipxe` before relying on this path again.

Once installed, either restore disk-first boot order or leave the server target on `local`. The latter makes PXE fall through to the disk without exposing an installer.

## How selection works

In `shared-router`, the router supplies the normal LAN address and the Mac's
ProxyDHCP reply supplies the HTTP boot URL. In `direct-cable`, the Mac supplies both
the lease and URL. In `esp-http`, local `autoexec.ipxe` already knows the stable URL.
All three reach the same `boot.ipxe`, which chains `selected.ipxe`; `bin/select`
changes that file atomically. This avoids blind keyboard timing on a headless
machine and the classic iPXE chainloading loop.

## Security and operational notes

- Installer SSH accepts only the public key configured by `SSH_PUBLIC_KEY_FILE`; no private key is copied.
- dnsmasq opens its privileged sockets as root, then drops to the invoking Mac user by default so it can read the project-local TFTP root. `PXE_SERVICE_USER` and `PXE_SERVICE_GROUP` can override this for a dedicated account.
- HTTP and TFTP are intentionally plain text. ProxyDHCP is MAC-restricted, but the
  generated HTTP files still assume the home LAN is trusted.
- `local` is the default and must remain the idle state.
- Verify the client disk before confirming any partitioning screen.
- Distro payloads come directly from vendor HTTPS endpoints on every boot. Their checksums/signatures are not pinned by this lab yet; add verification before treating it as a production provisioning system.

## Troubleshooting

Run `pxeboot doctor`, `pxeboot topology`, `pxeboot status`, and `pxeboot logs`. In
`shared-router`, the router/AP must bridge PXE broadcasts between Ethernet and
Wi-Fi; disable guest/client isolation if it blocks them. If firmware gets an
address but never loads iPXE, check UDP 69 and TFTP. If local iPXE loads but never
gets `boot.ipxe`, check UDP 4011/ProxyDHCP or install the ESP bootstrap and use
`esp-http`. Across VLANs, verify routing, DNS, ACLs, or a router DHCP relay. If an
installer boots but SSH is unreachable, use `pxeboot leases`, then check the public
key and macOS firewall.
