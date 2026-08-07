# Public boot tree

This directory contains the small, public files used by the persistent iPXE
client. Installer payloads are fetched directly from their upstream mirrors and
are not stored in GitHub.

The current selected target is Arch rescue. Its temporary root SSH account
accepts only the public key committed in `cloud-init/arch/user-data`.

Boot URL:

```text
https://raw.githubusercontent.com/wadew00/pxeboot-lab/main/public/boot.ipxe
```
