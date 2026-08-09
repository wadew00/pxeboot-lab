# This partial Kickstart selects the normal Fedora Workstation desktop.
# Installation and storage choices remain interactive over RDP.
url --metalink="https://mirrors.fedoraproject.org/metalink?repo=fedora-44&arch=x86_64"

sshpw --username=root --sshkey "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK6pGW9SXfS6TxPn/KD46lmqlkxNcw2frLr1XCwsNg3U wadew-local"
sshkey --username=root "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK6pGW9SXfS6TxPn/KD46lmqlkxNcw2frLr1XCwsNg3U wadew-local"

services --enabled=sshd
firewall --enabled --service=ssh --port=3389:tcp

%packages
@^workstation-product-environment
openssh-server
gnome-remote-desktop
%end

%post
systemctl set-default graphical.target
%end
