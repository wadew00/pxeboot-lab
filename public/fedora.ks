# This partial Kickstart selects the official Fedora Workstation desktop and
# authorizes the temporary installer maintenance shell. Installation and
# storage choices remain interactive over RDP.
sshpw --username=root --sshkey "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK6pGW9SXfS6TxPn/KD46lmqlkxNcw2frLr1XCwsNg3U wadew-local"

%packages
@^workstation-product-environment
%end

%post
systemctl set-default graphical.target
%end
