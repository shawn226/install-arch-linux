#!/bin/bash

set -e

echo "[ALIS] This is the second part of the Arch Linux Install Script"
echo ""

#############
# Fonctions #
#############

set_locale(){
    sed -i "s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" /etc/locale.gen
    locale-gen
    echo LANG=en_US.UTF-8 > /etc/locale.conf
    export LANG=en_US.UTF-8

    echo ""
    echo "[ALIS] Locale set successfully !"
    sleep 1
}

set_hostname(){
    local hostname=""

    read -p "[ALIS] Choose a hostname : " hostname
    echo $hostname > /etc/hostname

    echo "
127.0.0.1	localhost
::1		localhost
127.0.1.1	$hostname.localdomain	$hostname" >> /etc/hosts

}

create_user(){
    local username=""
    local password=""
    local valid_pwd=""
    local error=1

    while [ $error = 1 ]
    do
        read -p "[ALIS] Choose the name for the new user : " username
        if [[ -z $username ]]
        then
            echo "[ERROR] Choose a valid username !"
        else
            error=0
        fi
    done

    error=1

    while [ $error = 1 ]
    do  
        read -sp "[ALIS] Choose the password for the new user : " password
        echo ""
        read -sp "[ALIS] Confirm the password : " valid_pwd
    
        if [[ -z $password ]] || [[ $password != $valid_pwd ]]
        then
            echo ""
            echo "[ERROR] Password not valid !"
            echo ""
        else
            error=0
        fi
    done


    useradd -m -G wheel -s /bin/bash $username # create the user with group (sudo) Wheel

    echo $username:$password | chpasswd
 
    echo ""
    echo "[ALIS] The user has been created with success !"

    sleep 1

}

config_mkinit(){
    local hooks=$(grep "^HOOKS" /etc/mkinitcpio.conf)
    sed -i "s/MODULES=()/MODULES=(ext4 ext3 btrfs)/" /etc/mkinitcpio.conf
    sed -i "s/$hooks/HOOKS=\"base udev autodetect modconf block keymap encrypt lvm2 filesystems keyboard fsck\"/" /etc/mkinitcpio.conf

    mkinitcpio -p linux
}

config_bootloader(){
    local disk_name=$(fdisk -l | grep -v "rom\|loop\|airoot" | grep -m 1 "Disk" | awk -F' ' '{print $2}'| awk -F'/' '{print $3}'| awk -F':' '{print $1}')
    local uuid_crypt=$(lsblk -dno UUID /dev/${disk_name}2)

    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub_uefi --recheck
    sed -i "s/GRUB_CMDLINE_LINUX=\"\"/GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$uuid_crypt:luks:allow-discards\"/" /etc/default/grub

    grub-mkconfig -o /boot/grub/grub.cfg
    efibootmgr -c -g -d /dev/$disk_name -p 1 -w -L "Arch Linux (GRUB)" -l /EFI/grub_uefi/grubx64.efi
}

########
# Main #
########

timezone=$(curl -s ipinfo.io | jq ".timezone" | awk -F'"' '{print $2}')

# Make the timezone persistant
ln -s /usr/share/zoneinfo/$timezone /etc/localtime

set_locale

# Set the hardware clock mode
hwclock --systohc --utc

set_hostname

create_user

# Uncomment to create a sudo group
sed -i "s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/" /etc/sudoers

config_mkinit

config_bootloader


