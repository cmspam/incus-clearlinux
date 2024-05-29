# incus-clearlinux
Install script for incus on clearlinux (using Nix package manager)

# What does it do?

You can look at the script to see exactly what commands are used, but in general summary:

1. Installs dhcp-server kvm-host storage-utils which are all necessary for incus.
2. Installs nix package manager, and installs incus-lts along with some packages it needs (lxcfs, rsync, attr) with nix package manager.
3. Installs the incus UI from my repository here: https://github.com/cmspam/incus-ui
4. Sets up and enables systemd services to run incus and lxcfs

# How to use it

To minimize any potential issues, only use this script on a fresh clear linux installation.

I make it available publicly, but please note that this script does not have any kind of safety checking and is thrown together for my own convenience, so upstream changes, a lack of internet connectivity, or other various issues could potentially cause it to not work, or in the worst case, to harm your system.

I suggest you look at the script and run the commands line by line for the safest method of installation.

However, if you want to take the risk, you can get a root shell and run:
```
sudo su
bash <(curl -L https://raw.githubusercontent.com/cmspam/incus-clearlinux/main/incus-clearlinux-install.sh)
```


# Post-install maintenance.

Clearlinux and its packages will be updated automatically by default, but you can run
```
swupd update
```
in order to manually update.

The nix packages can be updated using
```
nix-channel --update
nix-env -u '*'
nix-collect-garbage -d
```

The UI can be updated by running:
```
curl -OL https://github.com/cmspam/incus-ui/releases/download/latest/incus-ui.tar.gz
tar xvf incus-ui.tar.gz
rm incus-ui.tar.gz
```
