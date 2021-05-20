#!/bin/bash

## Archcraft Chrooted Post Installation script
## Modified by Aditya Shakya (@adi1090x)
## Originally Made by fernandomaroto and manuel

# Any failed command will just be skiped, error message may pop up but won't crash the install process
# Net-install creates the file /tmp/run_once in live environment (need to be transfered to installed system) so it can be used to detect install option

# Get new user's username
new_user=`cat /etc/passwd | grep "/home" | cut -d: -f1 | head -1`

_check_internet_connection() {
    curl --silent --connect-timeout 8 https://8.8.8.8 > /dev/null
}

_is_pkg_installed() {
    # returns 0 if given package name is installed, otherwise 1
    local pkgname="$1"
    pacman -Q "$pkgname" >& /dev/null
}

_remove_a_pkg() {
    local pkgname="$1"
    pacman -Rsn --noconfirm "$pkgname"
}

_remove_pkgs_if_installed() {
    # removes given package(s) and possible dependencies if the package(s) are currently installed
    local pkgname
    for pkgname in "$@" ; do
        _is_pkg_installed "$pkgname" && _remove_a_pkg "$pkgname"
    done
}

## Detects if running in vbox
_vbox() {
    # packages must be in this order otherwise guest-utils pulls dkms, which takes longer to be installed
    local _vbox_guest_packages=(virtualbox-guest-dkms virtualbox-guest-utils)   
    local xx

    lspci | grep -i "virtualbox" >/dev/null
    if [[ "$?" != 0 ]] ; then
        for xx in ${_vbox_guest_packages[*]} ; do
            test -n "`pacman -Q $xx 2>/dev/null`" && pacman -Rnsdd $xx --noconfirm
        done
        rm -f /usr/lib/modules-load.d/virtualbox-guest-dkms.conf
    fi
}

## Detects if running in vmware
_vmware() {
    local vmware_guest_packages=(
        open-vm-tools
        xf86-input-vmmouse
        xf86-video-vmware
    )
    local xx

    case "`device-info --vga`" in
        VMware*)
            echo "[*] VMware Found."
            ;;
        *) 
            for xx in "${vmware_guest_packages[@]}" ; do
                test -n "`pacman -Q "$xx" 2>/dev/null`" && pacman -Rnsdd "$xx" --noconfirm
            done
            ;;
    esac
}

## Enable / disable systemd services
_common_systemd() {
    local _systemd_enable=(NetworkManager cups avahi-daemon systemd-timesyncd lxdm-plymouth)   
    local _systemd_disable=(multi-user.target livecd-alsa-unmuter livecd-talk)           
    local srv

	[[ `lspci | grep -i virtualbox` ]] && systemctl enable vboxservice

    for srv in ${_systemd_enable[*]};  do systemctl enable -f $srv; done
    for srv in ${_systemd_disable[*]}; do systemctl disable -f $srv; done
}

## Journals
_sed_stuff() {
    # Journal for offline. Turn volatile (for iso) into a real system.
    sed -i 's/volatile/auto/g' /etc/systemd/journald.conf 2>>/tmp/.errlog
    sed -i 's/.*pam_wheel\.so/#&/' /etc/pam.d/su
}

## Clean live ISO stuff from installed system
_clean_archiso() {

    local _files_to_remove=(                               
        /etc/sudoers.d/g_wheel
        /var/lib/NetworkManager/NetworkManager.state
        /etc/systemd/system/{livecd-alsa-unmuter.service,livecd-talk.service,etc-pacman.d-gnupg.mount,getty@tty1.service.d}
        /etc/systemd/system/getty@tty1.service.d/autologin.conf
        /root/{.automated_script.sh,.zlogin}
        /etc/mkinitcpio-archiso.conf
        /etc/polkit-1/rules.d/49-nopasswd-calamares.rules
        /etc/initcpio
        /etc/{group-,gshadow-,passwd-,shadow-}
        /etc/udev/rules.d/81-dhcpcd.rules
        /home/"$new_user"/{.xinitrc,.xsession,.xprofile,.wget-hsts,.screenrc,.ICEauthority}
        /root/{.xinitrc,.xsession,.xprofile}
        /etc/skel/{.xinitrc,.xsession,.xprofile}
        /etc/motd
		/usr/share/applications/xfce4-about.desktop
		/usr/local/bin/{Installation_guide,livecd-sound}
		/usr/local/share/livecd-sound
        /{gpg.conf,gpg-agent.conf,pubring.gpg,secring.gpg}
    )

    local xx

    for xx in ${_files_to_remove[*]}; do rm -rf $xx; done

    find /usr/lib/initcpio -name archiso* -type f -exec rm '{}' \;

}

## Remove unnecessary packages
_clean_offline_packages() {

    local _packages_to_remove=( 
    archcraft-installer
    calamares-config
    calamares
    archinstall
    qt5-declarative
    ckbcomp
    boost
    mkinitcpio-archiso
    squashfs-tools
    darkhttpd
    irssi
    lftp
    kitty-terminfo
    termite-terminfo
    lynx
    mc
    arch-install-scripts
    ddrescue
    testdisk
    syslinux
)
    local xx
    # @ does one by one to avoid errors in the entire process
    # * can be used to treat all packages in one command
    for xx in ${_packages_to_remove[@]}; do pacman -Rnscv $xx --noconfirm; done
}

## Remove un-wanted graphics drivers
_remove_other_graphics_drivers() {
    local graphics="`device-info --vga ; device-info --display`"
    local amd=no

    # remove Intel graphics driver if it is not needed
    if [[ -z "`echo "$graphics" | grep "Intel Corporation"`" ]] ; then
        _remove_pkgs_if_installed xf86-video-intel
    fi

    # remove AMD graphics driver if it is not needed
    if [[ -n "`echo "$graphics" | grep "Advanced Micro Devices"`" ]] ; then
        amd=yes
    elif [[ -n "`echo "$graphics" | grep "AMD/ATI"`" ]] ; then
        amd=yes
    elif [[ -n "`echo "$graphics" | grep "Radeon"`" ]] ; then
        amd=yes
    fi
    if [[ "$amd" = "no" ]] ; then
        _remove_pkgs_if_installed xf86-video-amdgpu xf86-video-ati
    fi
}

## Remove Nvidia Packages
_manage_nvidia_packages() {
    local file=/tmp/nvidia-info.bash        # nvidia info from livesession
    local nvidia_card=""                    # these two variables are defined in $file
    local nvidia_driver=""

    if [[ ! -r $file ]] ; then
        echo "[?] Warning: file $file does not exist!"

        if [[ 1 -eq 1 ]] ; then       # this line: change first 1 to 0 when old code is not needed
            echo "[!] Info: running the old nvidia mgmt code instead."
            if [[ -z "`lspci -k | grep -P 'VGA|3D|Display' | grep -w NVIDIA`" ]] || [[ -z "`lspci -k | grep -B2 "Kernel driver in use: nvidia" | grep -P 'VGA|3D|Display'`" ]] ; then
                local xx="`pacman -Qqs nvidia* | grep ^nvidia`"
                test -n "$xx" && pacman -Rsn $xx --noconfirm && pacman -Rsn --noconfirm xf86-video-nouveau
            fi
        fi
        return
    fi

    source $file

    case "$nvidia_card" in
        yes)
            echo "[*] Nvidia is detected."
            ;;
        no)
            local remove="`pacman -Qqs nvidia* | grep ^nvidia`"
            [[ "$remove" != "" ]] && pacman -Rsn --noconfirm $remove && pacman -Rsn --noconfirm xf86-video-nouveau
            ;;
    esac
}

## Remove broadcom wifi driver if not needed
_remove_broadcom_wifi_driver() {
    local pkgname=broadcom-wl-dkms
    local wifi_pci
    local wifi_driver

    _is_pkg_installed $pkgname && {
        wifi_pci="`lspci -k | grep -A4 " Network controller: "`"
        if [[ -n "`lsusb | grep " Broadcom "`" ]] || [[ -n "`echo "$wifi_pci" | grep " Broadcom "`" ]] ; then
            return
        fi
        wifi_driver="`echo "$wifi_pci" | grep "Kernel driver in use"`"
        if [[ -n "`echo "$wifi_driver" | grep "in use: wl$"`" ]] ; then
            return
        fi
        _remove_a_pkg "$pkgname"
    }
}

## Check if script exists and run or complain
_run_if_exists_or_complain() {
    local app="$1"

    if (which "$app" >& /dev/null) ; then
        echo "[*] Info: running $*"
        "$@"
    else
        echo "[!] Warning: program $app not found."
    fi
}

## Fix various grub stuff
_fix_grub_stuff() {
    _run_if_exists_or_complain ac-hooks-runner
    _run_if_exists_or_complain ac-grub-fix-initrd-generation
}

## Remove un-wanted ucode package
_remove_ucode() {
    local ucode="$1"
    pacman -Q $ucode >& /dev/null && {
        pacman -Rsn $ucode --noconfirm >/dev/null
    }
}

## Clean up
_clean_up() {
    local xx

    # Remove the "wrong" microcode.
    if [[ -x /usr/bin/device-info ]] ; then
        case "`/usr/bin/device-info --cpu`" in
            GenuineIntel) _remove_ucode amd-ucode ;;
            *)            _remove_ucode intel-ucode ;;
        esac
    fi

    # Fix various grub stuff.
    _fix_grub_stuff

    # remove nvidia graphics stuff
    _manage_nvidia_packages

    # remove AMD and Intel graphics drivers if they are not needed
    _remove_other_graphics_drivers

    # remove broadcom-wl-dkms if it is not needed
    _remove_broadcom_wifi_driver

    # keep r8168 package but blacklist it; r8169 will be used by default
    xx=/usr/lib/modprobe.d/r8168.conf
    test -r $xx && sed -i $xx -e 's|r8169|r8168|'

    # delete some files after offline install
    rm -rf /usr/share/calamares
}

########################################
########## SCRIPT STARTS HERE ##########
########################################

_clean_archiso
_sed_stuff
_clean_offline_packages
_common_systemd
_vbox
_vmware
_clean_up

## Remove these scripts from installed system
rm -rf /usr/bin/{post_install.sh,chrooted_post_install.sh,abif_post_install.sh,abif_chrooted_post_install.sh}
