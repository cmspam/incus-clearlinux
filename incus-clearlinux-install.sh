#!/usr/bin/env bash

LOG_FILE="incus_install.log"
BYPASS_PROMPT=0
VERSION_TYPE=""

if [ "$1" == "--yes" ]; then
    BYPASS_PROMPT=1
fi

if [ -x /opt/incus/systemd/incusd ]; then
   echo "/opt/incus/systemd/incusd already exists."
   echo "Have you already installed incus?"
   echo "Please remove /opt/incus and run this script again."
   echo "Exiting..."
   exit 0
fi

select_version() {
    while true; do
        echo "Please select the version you would like to install:"
        echo "1. Stable - The latest stable version"
        echo "2. LTS - The long-term supported version"
        read -p "Enter your choice (1 or 2): " version_choice
        case $version_choice in
            1)
                VERSION_TYPE="stable"
                return 0
                ;;
            2)
                VERSION_TYPE="lts"
                return 0
                ;;
            *)
                echo "Invalid choice. Please enter 1 or 2."
                ;;
        esac
    done
}

if [ -x /usr/bin/swupd ]; then
    if [ $BYPASS_PROMPT -eq 0 ]; then
        select_version
        
        echo "This script will install the following:"
        echo
        echo "1.  NixOS Package Manager (in the /nix folder)"
        if [ "$VERSION_TYPE" == "stable" ]; then
            echo "2.  Incus Stable (as a Nix package, with some other files in /opt/incus)"
        else
            echo "2.  Incus LTS (as a Nix package, with some other files in /opt/incus)"
        fi
        echo "3.  Incus UI (in /opt/incus/ui)"
        echo "4.  incus.service and incus-ui.service systemd services"
        echo "5.  dhcp-server, vm-host, and storage-utils packages (needed for incus functionality)"
        echo "6.  lxcfs, rsync, attr with Nix (incus dependencies)"
        echo
        read -p "Do you want to continue? (N/y): " REPLY
        if [ "${REPLY,,}" != "y" ]; then
            echo "Exiting..."
            exit 0
        fi
    fi

    echo "Installing dhcp-server, kvm-host, and storage-utils packages..." | tee -a "$LOG_FILE"
    echo "(This can take a long time. Please be patient.)"
    swupd bundle-add dhcp-server kvm-host storage-utils >> "$LOG_FILE" 2>&1

    echo "Creating /etc/tmpfiles.d directory..." | tee -a "$LOG_FILE"
    mkdir -p /etc/tmpfiles.d

    echo "Installing NixOS Package Manager..." | tee -a "$LOG_FILE"
    sh <(curl -L https://nixos.org/nix/install) --daemon --yes >> "$LOG_FILE" 2>&1

    echo "Adding /etc/bashrc to /etc/profile for compatibility..." | tee -a "$LOG_FILE"
    if [ -f /etc/profile ]; then
        cp /etc/profile /etc/profile.backup
        if [ -f /etc/profile.backup ]; then
            echo "Backup of /etc/profile created successfully."
        else
            echo "Failed to create backup of /etc/profile."
            exit 1
        fi
    else
        echo "/etc/profile does not exist. No backup needed."
    fi

    cat /etc/bashrc >> /etc/profile

    source /etc/bashrc

    echo "Updating Nix channels..." | tee -a "$LOG_FILE"
    nix-channel --update >> "$LOG_FILE" 2>&1

    if [ "$VERSION_TYPE" == "stable" ]; then
        echo "Installing attr, incus, rsync, and lxcfs..." | tee -a "$LOG_FILE"
        nix-env -i attr incus rsync lxcfs >> "$LOG_FILE" 2>&1
    else
        echo "Installing attr, incus-lts, rsync, and lxcfs..." | tee -a "$LOG_FILE"
        nix-env -i attr incus-lts rsync lxcfs >> "$LOG_FILE" 2>&1
    fi

    echo "Setting up /etc/subuid and /etc/subgid..." | tee -a "$LOG_FILE"
    echo "root:100000:65536" > /etc/subuid
    echo "root:100000:65536" > /etc/subgid

    echo "Creating /opt/incus/systemd directory..." | tee -a "$LOG_FILE"
    mkdir -p /opt/incus/systemd
    echo "Creating /var/log/incus/incusd.log file..." | tee -a "$LOG_FILE"
    mkdir -p /var/log/incus
    touch /var/log/incus/incusd.log

    echo "#!/bin/bash" > /opt/incus/systemd/incusd
    cat /etc/bashrc >> /opt/incus/systemd/incusd
    echo "export INCUS_OVMF_PATH=/usr/share/qemu/" >> /opt/incus/systemd/incusd
    echo "export INCUS_EDK2_PATH=/usr/share/qemu/" >> /opt/incus/systemd/incusd    
    echo "export INCUS_UI=/opt/incus/ui/" >> /opt/incus/systemd/incusd
    echo "exec incusd \"\$@\"" >> /opt/incus/systemd/incusd

    echo "#!/bin/bash" > /opt/incus/systemd/lxcfs
    cat /etc/bashrc >> /opt/incus/systemd/lxcfs
    echo "exec lxcfs \"\$@\"" >> /opt/incus/systemd/lxcfs

    echo "Making incusd and lxcfs executable..." | tee -a "$LOG_FILE"
    chmod +x /opt/incus/systemd/incusd
    chmod +x /opt/incus/systemd/lxcfs

    echo "Creating /var/lib/incus and /var/lib/lxcfs directories..." | tee -a "$LOG_FILE"
    mkdir -p /var/lib/incus
    mkdir -p /var/lib/lxcfs

    echo "Downloading Incus UI..." | tee -a "$LOG_FILE"
    if [ "$VERSION_TYPE" == "stable" ]; then
        curl -OL https://github.com/cmspam/incus-ui/releases/download/latest/incus-ui-stable.tar.gz >> "$LOG_FILE" 2>&1
        tar xvf incus-ui-stable.tar.gz -C /opt/incus/
        rm incus-ui-stable.tar.gz
    else
        curl -OL https://github.com/cmspam/incus-ui/releases/download/latest/incus-ui-lts.tar.gz >> "$LOG_FILE" 2>&1
        tar xvf incus-ui-lts.tar.gz -C /opt/incus/
        rm incus-ui-lts.tar.gz
    fi

    echo "Creating /etc/systemd/system directory..." | tee -a "$LOG_FILE"
    mkdir -p /etc/systemd/system

    echo "Creating incus-lxcfs.service file..." | tee -a "$LOG_FILE"
    cat << EOF > /etc/systemd/system/incus-lxcfs.service
[Unit]
Description=Incus - LXCFS daemon
ConditionVirtualization=!container
Before=incus.service

[Service]
OOMScoreAdjust=-1000
ExecStartPre=-/bin/mkdir -p /var/lib/lxcfs
ExecStart=/opt/incus/systemd/lxcfs /var/lib/lxcfs
KillMode=process
Restart=on-failure
Delegate=yes
ExecReload=/bin/kill -USR1 \$MAINPID

[Install]
WantedBy=multi-user.target
EOF

    echo "Creating incus.service file..." | tee -a "$LOG_FILE"
    cat << EOF > /etc/systemd/system/incus.service
[Unit]
Description=Incus - Daemon
After=network-online.target openvswitch-switch.service incus-lxcfs.service
Requires=network-online.target incus-lxcfs.service

[Service]
ExecStart=/opt/incus/systemd/incusd --logfile /var/log/incus/incusd.log
ExecStartPost=/opt/incus/systemd/incusd waitready --timeout=600
KillMode=process
TimeoutStartSec=600s
TimeoutStopSec=30s
Restart=on-failure
Delegate=yes
LimitNOFILE=1048576
LimitNPROC=infinity
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOF

    echo "Enabling and starting incus-lxcfs service..." | tee -a "$LOG_FILE"
    systemctl enable --now incus-lxcfs

    echo "Enabling and starting incus service..." | tee -a "$LOG_FILE"
    systemctl enable --now incus

    echo "INSTALLATION IS FINISHED" | tee -a "$LOG_FILE"
    if [ "$VERSION_TYPE" == "stable" ]; then
        echo "Installed Incus Stable version" | tee -a "$LOG_FILE"
    else
        echo "Installed Incus LTS version" | tee -a "$LOG_FILE"
    fi
    echo "Please run 'incus admin init' and set up incus. You may need to log out and log in first." | tee -a "$LOG_FILE"
    echo "You can examine the log file '$LOG_FILE' if anything seems wrong."
else
    echo "/usr/bin/swupd does not exist. Exiting."
    exit 1
fi
