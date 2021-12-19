#!/bin/bash

# set -e

echo "[ALIS] Welcome to Arch Install Script by Shawn226."
echo "[ALIS] Answer the followed questions."

#############
# Variables #
#############
keyboard=""
timezone=""
disk_name=""
disk_size=""
disk_ext=""


#############
# Fonctions #
#############

# Know the firmware of the motherboard - pref EFI
mb_firmware(){ 
    if [[ -d "/sys/firmware/efi/efivars" ]]
    then
        echo "[ALIS] EFI firmware detected"
	else
        echo "[ERROR] Please change the firmware to EFI boot (without secure boot)"
		exit
    fi
}

# Change the keyboard layout
change_kb_layout(){
    echo "" # new line
    local error=1
    while [ $error = 1 ]
    do
        read -p "Choose the keyboard layout : " keyboard
        loadkeys $keyboard 2> /dev/null

        if [ $? = 0 ]
        then
            echo "[ALIS] New keyboard layout has been updated !"
            error=0
        else
            echo "[ERROR] Unknow keyboard layout ! Start over."
        fi
    done
}

# Set timezone
set_timezone(){
    yes | pacman -S jq
    timezone=$(curl -s ipinfo.io | jq ".timezone" | awk -F'"' '{print $2}')
    timedatectl set-timezone $timezone
    timedatectl set-ntp 1
    echo "[ALIS] New timezone has been selected !"
    timedatectl
}

# Disks detection
detect_disk(){
    disk_name=$(fdisk -l | grep -v "rom\|loop\|airoot" | grep -m 1 "Disk" | awk -F' ' '{print $2}'| awk -F'/' '{print $3}'| awk -F':' '{print $1}')
    disk_size=$(fdisk -l | grep -v "rom\|loop\|airoot" | grep -m 1 "Disk" | awk -F' ' '{print $3}')
    disk_ext=$(fdisk -l | grep -v "rom\|loop\|airoot" | grep -m 1 "Disk" | awk -F' ' '{print $4}' | awk -F',' '{print $1}')

    echo "[ALIS] Hardware detected : $disk_name $disk_size$disk_ext"

    disk_size=$((${disk_size}-4))
}

# Partitioning
partitioning(){

    ( echo g; echo n; echo 1; echo ""; echo +550M; echo t; echo 1; echo w ) | fdisk /dev/$disk_name &> /dev/null # Create boot partition
    sleep 1
    ( echo n; echo 2; echo ""; echo ""; echo w ) | fdisk /dev/$disk_name &> /dev/null # Create the encrypted partition
    
    sleep 1

    mkfs.vfat -F32 /dev/${disk_name}1 # make the FS for the boot partition, FAT32 for EFI
    e2label /dev/${disk_name}1 BOOT # Create boot label
   
    echo "" # New line
    echo "[ALIS] Encrypting the partition."
    echo "" # New line


    cryptsetup -c aes-xts-plain64 -q -y --use-random luksFormat /dev/${disk_name}2 # Encrypt the partition

    while [ $? != 0 ]
    do
        echo "[ERROR] The passphrases do not match !"
        cryptsetup -c aes-xts-plain64 -q -y --use-random luksFormat /dev/${disk_name}2 # Encrypt the partition
    done
    
    echo "" # New line
    echo "[ALIS] Open the encrypted partition."
    echo "" # New line
    cryptsetup luksOpen /dev/${disk_name}2 decrypted # Open the encrypted partition

    pvcreate /dev/mapper/decrypted # Create the physical volume
    vgcreate VG_CRYPT /dev/mapper/decrypted # Create the VG group

    lvcreate --size $(($(echo 40*${disk_size}/100)))G VG_CRYPT --name lv_root # Create logical volume for root 40%
    lvcreate --size $(($(echo 40*${disk_size}/100)))G VG_CRYPT --name lv_home # Create logical volume for home 40%
    lvcreate --size $(($(echo 20*${disk_size}/100)))G VG_CRYPT --name lv_var # Create logical volume for var 20%
    lvcreate --size 2G VG_CRYPT --name lv_tmp # Create logical volume for tmp ~5%
    lvcreate --size 2G VG_CRYPT --name lv_swap # Create logical volume for swap

    # Assign file system 
    mkfs.ext4 /dev/mapper/VG_CRYPT-lv_root -L ROOT
    mkfs.btrfs /dev/mapper/VG_CRYPT-lv_home -L HOME
    mkfs.ext4 /dev/mapper/VG_CRYPT-lv_var -L Var
    mkfs.ext3 /dev/mapper/VG_CRYPT-lv_tmp -L TMP
    mkswap /dev/mapper/VG_CRYPT-lv_swap
    swaplabel -L SWAP /dev/mapper/VG_CRYPT-lv_swap

    # Mount FS
    mount /dev/mapper/VG_CRYPT-lv_root /mnt # Mount root first

    mkdir /mnt/boot /mnt/home /mnt/var /mnt/tmp # Create dir for chroot
    swapon /dev/mapper/VG_CRYPT-lv_swap
    mount /dev/mapper/VG_CRYPT-lv_home /mnt/home
    mount /dev/mapper/VG_CRYPT-lv_var /mnt/var
    mount /dev/mapper/VG_CRYPT-lv_tmp /mnt/tmp
    mount /dev/${disk_name}1 /mnt/boot
    
    lsblk -fe7 # Display partitions with FS
    sleep 2
}

set_mirror(){
    ( echo n) | pacman -Syu 2> /dev/null
    yes | pacman -S jq
    local country=$(curl -s ipinfo.io | jq ".country" | awk -F'"' '{print $2}')
    reflector --country $country > /etc/pacman.d/mirrorlist
}

########
# Main #
########

mb_firmware
change_kb_layout
detect_disk

sleep 1

partitioning
set_mirror
set_timezone

# Install the system for chroot
pacstrap /mnt base base-devel linux linux-firmware openssh jq git vim lvm2 grub efibootmgr

# Generate the Fstab
genfstab -pU /mnt >> /mnt/etc/fstab

echo "KEYMAP=$keyboard" > /mnt/etc/vconsole.conf

cp "install_arch_linux (chroot) - part 2.sh" /mnt/

chmod +x /mnt/install_arch_linux\ \(chroot\)\ -\ part\ 2.sh

arch-chroot /mnt ./install_arch_linux\ \(chroot\)\ -\ part\ 2.sh

umount -R /mnt

swapoff -a

shutdown now

