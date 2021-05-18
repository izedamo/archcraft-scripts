#!/bin/bash

## Archcraft Post Installation script
## Modified by Aditya Shakya (@adi1090x)
## Originally Made by fernandomaroto for EndeavourOS and Portergos
## Adapted from AIS. An excellent bit of code.

# Get calamares chroot path
MOUNTPOINT='/mnt'

# Get new user's username
new_user=`cat ${MOUNTPOINT}/etc/passwd | grep "/home" | cut -d: -f1 | head -1`

# Copy files and directory from live environment to new system
cp -rf /etc/environment ${MOUNTPOINT}/etc/environment
mkdir -p ${MOUNTPOINT}/boot/grub/themes
cp -rf /usr/share/grub/themes/default ${MOUNTPOINT}/boot/grub/themes

_copy_files(){
	# copy lxdm config file
    local lxdm_config=/etc/lxdm/lxdm.conf
    if [[ -x ${MOUNTPOINT}/usr/bin/lxdm ]] ; then
        echo "[*] Copying $lxdm_config config file..."
        rsync -vaRI "$lxdm_config" ${MOUNTPOINT}
    fi

	# copy os-release file
    local os_file=/usr/lib/os-release
    if [[ -r "$os_file" ]] ; then
        if [[ ! -r ${MOUNTPOINT}${file} ]] ; then
            echo "[*] Copying $os_file to target"
            rsync -vaRI "$os_file" ${MOUNTPOINT}
        fi
    else
        echo "Error: file $os_file does not exist, copy failed!"
        return
    fi

    # Communicate to chrooted system if
    # - nvidia card is detected
    # - livesession is running nvidia driver
    local nvidia_file=${MOUNTPOINT}/tmp/nvidia-info.bash
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
