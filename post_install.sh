#!/bin/bash

## Archcraft Post Installation script
## Modified by Aditya Shakya (@adi1090x)
## Originally Made by fernandomaroto for EndeavourOS and Portergos
## Adapted from AIS. An excellent bit of code.

# Get calamares chroot path
chroot_path=`lsblk | grep "calamares-root" | awk '{ print $NF }' | sed -e 's/\/tmp\///' -e 's/\/.*$//' | tail -n1`

if [[ -z "$chroot_path" ]] ; then
    echo "Fatal error: `basename $0`: chroot_path is empty!"
fi

# Get new user's username
new_user=`cat /tmp/$chroot_path/etc/passwd | grep "/home" | cut -d: -f1 | head -1`

arch_chroot() {
	# Use chroot not arch-chroot because of the way calamares mounts partitions
    chroot /tmp/"$chroot_path" /bin/bash -c "${1}"
}

# Copy files and directory from live environment to new system
cp -rf /etc/environment /tmp/"$chroot_path"/etc/environment
mkdir -p /tmp/"$chroot_path"/boot/grub/themes
cp -rf /usr/share/grub/themes/default /tmp/"$chroot_path"/boot/grub/themes

_copy_files(){
	# copy lxdm config file
    local lxdm_config=/etc/lxdm/lxdm.conf
    if [[ -x /tmp/"$chroot_path"/usr/bin/lxdm ]] ; then
        echo "[*] Copying $lxdm_config config file..."
        rsync -vaRI "$lxdm_config" /tmp/"$chroot_path"
    fi

	# copy os-release file
    local os_file=/usr/lib/os-release
    if [[ -r "$os_file" ]] ; then
        if [[ ! -r /tmp/"$chroot_path"${file} ]] ; then
            echo "[*] Copying $os_file to target"
            rsync -vaRI "$os_file" /tmp/"$chroot_path"
        fi
    else
        echo "Error: file $os_file does not exist, copy failed!"
        return
    fi

    # Communicate to chrooted system if
    # - nvidia card is detected
    # - livesession is running nvidia driver
    local nvidia_file=/tmp/"$chroot_path"/tmp/nvidia-info.bash
    local card=no
    local driver=no
    local lspci="`lspci -k`"

    if [[ -n "`echo "$lspci" | grep -P 'VGA|3D|Display' | grep -w NVIDIA`" ]] ; then
        card=yes
        [[ -n "`lsmod | grep -w nvidia`" ]]                                                   && driver=yes
        [[ -n "`echo "$lspci" | grep -wA2 NVIDIA | grep "Kernel driver in use: nvidia"`" ]]   && driver=yes
    fi
    echo "nvidia_card=$card"     >> $nvidia_file
    echo "nvidia_driver=$driver" >> $nvidia_file
}

## Main Execution
_copy_files

## Run the following script inside calamares chroot (target system)
## For chrooted commands edit the script bellow directly
arch_chroot "/usr/bin/chrooted_post_install.sh"
