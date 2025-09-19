#!/usr/bin/env bash
# Automated Arch Linux Install with Btrfs, Timeshift & grub-btrfs
# ⚠️ WARNING: This will WIPE the selected disk ⚠️

set -e

### --- User Prompts ---
read -rp "Enter target disk (e.g., /dev/sda): " DISK
read -rp "Enter hostname: " HOSTNAME
read -rp "Enter username: " USERNAME
read -srp "Enter root password: " ROOTPASS
echo
read -srp "Enter password for $USERNAME: " USERPASS
echo
read -rp "Enter timezone (e.g., Europe/Nicosia): " TIMEZONE
read -rp "Enter locale (default en_GB.UTF-8): " LOCALE
LOCALE=${LOCALE:-en_GB.UTF-8}
read -rp "Enter keymap (default uk): " KEYMAP
KEYMAP=${KEYMAP:-uk}

### --- Partitioning ---
echo ">>> Partitioning disk $DISK..."
sgdisk -Z $DISK
sgdisk -n 1:0:+550M -t 1:ef00 -c 1:"EFI" $DISK
sgdisk -n 2:0:0 -t 2:8300 -c 2:"ROOT" $DISK

EFI="${DISK}1"
ROOT="${DISK}2"

### --- Formatting ---
echo ">>> Formatting partitions..."
mkfs.fat -F32 $EFI
mkfs.btrfs -f $ROOT

### --- Subvolumes ---
echo ">>> Creating Btrfs subvolumes..."
mount $ROOT /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@snapshots
umount /mnt

echo ">>> Mounting subvolumes..."
mount -o subvol=@ $ROOT /mnt
mkdir -p /mnt/{boot,home,var,.snapshots}
mount -o subvol=@home $ROOT /mnt/home
mount -o subvol=@var $ROOT /mnt/var
mount -o subvol=@snapshots $ROOT /mnt/.snapshots
mount $EFI /mnt/boot

### --- Base System ---
echo ">>> Installing base system..."
pacstrap /mnt base linux-lts linux-firmware vim sudo networkmanager btrfs-progs timeshift grub-btrfs

echo ">>> Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

### --- Chroot Configuration ---
echo ">>> Entering chroot..."
arch-chroot /mnt /bin/bash <<EOF
set -e

# Time & locale
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# Hostname
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOL
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOL

# Root password
echo "root:$ROOTPASS" | chpasswd

# User account
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$USERPASS" | chpasswd

# Sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Bootloader
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Services
systemctl enable NetworkManager
systemctl enable systemd-timesyncd
systemctl enable grub-btrfsd
EOF

echo ">>> Installation complete. Reboot after unmounting."
umount -R /mnt
