#! /bin/sh
set -e
# The script gets called with the following environment variables set:
# OSI_LOCALE              : Locale to be used in the new system
# OSI_DEVICE_PATH         : Device path at which to install
# OSI_DEVICE_IS_PARTITION : 1 if the specified device is a partition (0 -> disk)
# OSI_DEVICE_EFI_PARTITION: Set if device is partition and system uses EFI boot.
# OSI_USE_ENCRYPTION      : 1 if the installation is to be encrypted
# OSI_ENCRYPTION_PIN      : The encryption pin to use (if encryption is set)

# sanity check that all variables were set
if [ -z ${OSI_LOCALE+x} ] || \
   [ -z ${OSI_DEVICE_PATH+x} ] || \
   [ -z ${OSI_DEVICE_IS_PARTITION+x} ] || \
   [ -z ${OSI_DEVICE_EFI_PARTITION+x} ] || \
   [ -z ${OSI_USE_ENCRYPTION+x} ] || \
   [ -z ${OSI_ENCRYPTION_PIN+x} ]
then
    echo "Installer script called without all environment variables set!"
    exit 1
fi

echo 'Installation started.'
echo ''
echo 'Variables set to:'
echo 'OSI_LOCALE               ' $OSI_LOCALE
echo 'OSI_DEVICE_PATH          ' $OSI_DEVICE_PATH
echo 'OSI_DEVICE_IS_PARTITION  ' $OSI_DEVICE_IS_PARTITION
echo 'OSI_DEVICE_EFI_PARTITION ' $OSI_DEVICE_EFI_PARTITION
echo 'OSI_USE_ENCRYPTION       ' $OSI_USE_ENCRYPTION
echo 'OSI_ENCRYPTION_PIN       ' $OSI_ENCRYPTION_PIN
echo ''

# Pretending to do something
DEV=$OSI_DEVICE_PATH
if [[ $OSI_DEVICE_IS_PARTITION == 1 ]]
then
    echo 'Device is partition'
    DISK=$(lsblk $DEV -npdbro pkname)
    START=$(lsblk $DEV -npdbro START)
    SIZE=$[ $(lsblk $DEV -npdbro SIZE) / 512 ] #blockdev --getsz /dev/sda
    END=$[ START + SIZE - 1 ]
    echo 'Disk is' $DISK
    echo 'Start is' $START
    echo 'Size is' $SIZE
    echo 'End is' $END

    if [ -d /sys/firmware/efi/efivars/ ]
    then
        EFIPART=$(lsblk $DISK -npo PATH,PARTTYPENAME | grep "EFI System" | head -n 1 | awk '{print $1}')
        if [ -z $EFIPART ]
        then
            echo 'No EFI partition found on disk'
            (
              # Remove current partition
              echo d
              echo $DEV | awk '{print substr($0,length,1)}'
              echo p
              # EFI partition
              echo n
              echo
              echo $START
              echo +512M
              echo EF00
              echo p
              # Root partition
              echo n
              echo
              echo $[ START + 536870912/512 + 1 ]
              echo $[ END - 4294967296/512 ]
              echo
              echo p
              # Swap partition
              echo n
              echo
              echo $[ END - 4294967296/512 + 1 ]
              echo $END
              echo 8200
              echo p
              # Write changes
              echo w
              echo y
            ) | pkexec gdisk $DISK
            sleep 1
            EFIPART=$(lsblk $DISK -npbro PATH,PARTTYPENAME,START,SIZE | grep 'EFI\\x20System')
            echo 'INITIAL EFIPART' $EFIPART
            while IFS= read -r line; do
                LINESTART=$(echo -E $line | awk '{print $3}')
                LINESIZE=$[ $(echo -E $line | awk '{print $4}') / 512 ]
                if [[ $LINESTART -ge $START && $[ LINESTART + LINESIZE - 1 ] -le $END ]]
                then
                    EFIPART=$(echo -E $line | awk '{print $1}')
                    break
                fi
            done <<< "$EFIPART"
            FSPART=$(lsblk $DISK -npbro PATH,PARTTYPENAME,START,SIZE | grep 'Linux\\x20filesystem')
            while IFS= read -r line; do
                LINESTART=$(echo -E $line | awk '{print $3}')
                LINESIZE=$[ $(echo -E $line | awk '{print $4}') / 512 ]
                if [[ $LINESTART -ge $START && $[ LINESTART + LINESIZE -1 ] -le $END ]]
                then
                    FSPART=$(echo -E $line | awk '{print $1}')
                    break
                fi
            done <<< "$FSPART"
            SWAPPART=$(lsblk $DISK -npbro PATH,PARTTYPENAME,START,SIZE | grep 'Linux\\x20swap')
            while IFS= read -r line; do
                LINESTART=$(echo -E $line | awk '{print $3}')
                LINESIZE=$[ $(echo -E $line | awk '{print $4}') / 512 ]
                if [[ $LINESTART -ge $START && $[ LINESTART + LINESIZE -1 ] -le $END ]]
                then
                    SWAPPART=$(echo -E $line | awk '{print $1}')
                    break
                fi
            done <<< "$SWAPPART"
            if [ -z ${EFIPART+x} ] || [ -z ${FSPART+x} ] || [ -z ${SWAPPART+x} ]
            then
                echo 'EFI, root or swap partition not found'
                exit 1
            else
                pkexec mkfs.fat -F32 $EFIPART
                pkexec mkfs.ext4 -F $FSPART
                pkexec mkswap $SWAPPART
            fi
        else
            echo 'EFI partition is' $EFIPART
            (
              # Remove current partition
              echo d
              echo $DEV | awk '{print substr($0,length,1)}'
              echo p
              # Root partition
              echo n
              echo
              echo $START
              echo $[ END - 4294967296/512 ]
              echo
              echo p
              # Swap partition
              echo n
              echo
              echo $[ END - 4294967296/512 + 1]
              echo $END
              echo 8200
              echo p
              # Write changes
              echo w
              echo y
            ) | pkexec gdisk $DISK
            sleep 1
            FSPART=$(lsblk $DISK -npbro PATH,PARTTYPENAME,START,SIZE | grep 'Linux\\x20filesystem')
            while IFS= read -r line; do
                LINESTART=$(echo -E $line | awk '{print $3}')
                LINESIZE=$[ $(echo -E $line | awk '{print $4}') / 512 ]
                if [[ $LINESTART -ge $START && $[ LINESTART + LINESIZE - 1 ] -le $END ]]
                then
                    FSPART=$(echo -E $line | awk '{print $1}')
                    break
                fi
            done <<< "$FSPART"
            SWAPPART=$(lsblk $DISK -npbro PATH,PARTTYPENAME,START,SIZE | grep 'Linux\\x20swap')
            while IFS= read -r line; do
                LINESTART=$(echo -E $line | awk '{print $3}')
                LINESIZE=$[ $(echo -E $line | awk '{print $4}') / 512 ]
                if [[ $LINESTART -ge $START && $[ LINESTART + LINESIZE -1 ] -le $END ]]
                then
                    SWAPPART=$(echo -E $line | awk '{print $1}')
                    break
                fi
            done <<< "$SWAPPART"
            if [ -z ${EFIPART+x} ] || [ -z ${FSPART+x} ] || [ -z ${SWAPPART+x} ]
            then
                echo 'EFI, root or swap partition not found'
                exit 1
            else
                pkexec mkfs.ext4 -F $FSPART
                pkexec mkswap $SWAPPART
            fi
        fi
    else
        echo 'Device is in BIOS mode'
        (
          # Remove current partition
          echo d
          echo $DEV | awk '{print substr($0,length,1)}'
          echo p
          # Root partition
          echo n
          echo #primary
          echo #partition number
          echo $START
          echo $[ END - 4294967296/512 ]
          echo p
          # Swap partition
          echo n
          echo #primary
          echo #partition number
          echo $[ END - 4294967296/512 + 1]
          echo $END
          echo p
          # Write changes
          echo w
        ) | pkexec fdisk $DISK -W always
        sleep 1
        FSPART=$(lsblk $DISK -npbro PATH,PARTTYPENAME,START,SIZE | grep 'Linux')
        while IFS= read -r line; do
            LINESTART=$(echo -E $line | awk '{print $3}')
            LINESIZE=$[ $(echo -E $line | awk '{print $4}') / 512 ]
            if [[ $LINESTART -ge $START && $[ LINESTART + LINESIZE - 1 ] -le $END ]]
            then
                FSPART=$(echo -E $line | awk '{print $1}')
                break
            fi
        done <<< "$FSPART"
        SWAPPART=$(lsblk $DISK -npbro PATH,PARTTYPENAME,START,SIZE | grep 'Linux')
        while IFS= read -r line; do
            LINESTART=$(echo -E $line | awk '{print $3}')
            LINESIZE=$[ $(echo -E $line | awk '{print $4}') / 512 ]
            if [[ $LINESTART -ge $START && $[ LINESTART + LINESIZE -1 ] -le $END && $(echo -E $line | awk '{print $1}') != $FSPART ]]
            then
                SWAPPART=$(echo -E $line | awk '{print $1}')
                break
            fi
        done <<< "$SWAPPART"
        echo 'Filesystem partition is' $FSPART
        echo 'Swap partition is' $SWAPPART
        if [ -z ${FSPART+x} ] || [ -z ${SWAPPART+x} ]
        then
            echo 'Root or swap partition not found'
            exit 1
        else
            pkexec sfdisk --part-type $DISK $(echo $SWAPPART | awk '{print substr($0,length,1)}') 82
            pkexec mkfs.ext4 -F $FSPART
            pkexec mkswap $SWAPPART
        fi
    fi
else
    if [ -d /sys/firmware/efi/efivars/ ]
    then
        echo 'EFI mode'
        (
          # GPT partition table
          echo o
          echo y
          # EFI partition
          echo n
          echo
          echo
          echo +512M
          echo EF00
          # Root partition
          echo n
          echo
          echo
          echo -4G
          echo
          # Swap partition
          echo n
          echo
          echo
          echo
          echo 8200
          # Write changes
          echo w
          echo y
        ) | pkexec gdisk $DEV
        sleep 1
        EFIPART=$(lsblk $DEV -npbro PATH,PARTTYPENAME | grep 'EFI\\x20System' | head -n 1 | awk '{print $1}')
        FSPART=$(lsblk $DEV -npbro PATH,PARTTYPENAME | grep 'Linux\\x20filesystem' | head -n 1 | awk '{print $1}')
        SWAPPART=$(lsblk $DEV -npbro PATH,PARTTYPENAME | grep 'Linux\\x20swap' | head -n 1 | awk '{print $1}')
        echo "EFI partition is $EFIPART"
        echo "Root partition is $FSPART"
        echo "Swap partition is $SWAPPART"
        if [ -z ${EFIPART+x} ] || [ -z ${FSPART+x} ] || [ -z ${SWAPPART+x} ]
        then
            echo 'EFI, root or swap partition not found'
            exit 1
        else
            pkexec mkfs.fat -F32 $EFIPART
            pkexec mkfs.ext4 -F $FSPART
            pkexec mkswap $SWAPPART
        fi
    else
        echo 'Device is in BIOS mode'
        (
          # MSDOS partition table
          echo o
          # Root partition
          echo n
          echo #primary
          echo #part number
          echo #start
          echo -4G
          # Swap partition
          echo n
          echo #primary
          echo #part number
          echo #start
          echo #end
          echo t
          echo 2
          echo swap
          # Write changes
          echo w
        ) | pkexec fdisk $DEV -W always
        sleep 1
        FSPART=$(lsblk $DEV -npbro PATH,PARTTYPENAME | grep 'Linux' | head -n 1 | awk '{print $1}')
        SWAPPART=$(lsblk $DEV -npbro PATH,PARTTYPENAME | grep 'Linux\\x20swap\\x20/\\x20Solaris' | head -n 1 | awk '{print $1}')
        echo "Root partition is $FSPART"
        echo "Swap partition is $SWAPPART"
        if [ -z ${FSPART+x} ] || [ -z ${SWAPPART+x} ]
        then
            echo 'Root or swap partition not found'
            exit 1
        else
            pkexec mkfs.ext4 -F $FSPART
            pkexec mkswap $SWAPPART
        fi
    fi
fi

echo 'Mounting partitions...'
if [ -d /sys/firmware/efi/efivars/ ]
then
    echo 'EFI partition is' $EFIPART
fi
echo 'Filesystem partition is' $FSPART
echo 'Swap partition is' $SWAPPART
pkexec rm -rf /tmp/os-installer
pkexec mkdir -p /tmp/os-installer
pkexec mount $FSPART /tmp/os-installer
if [ -d /sys/firmware/efi/efivars/ ]
then
    pkexec mkdir -p /tmp/os-installer/boot/efi
    pkexec mount $EFIPART /tmp/os-installer/boot/efi
fi
pkexec swapon $SWAPPART
pkexec nixos-generate-config --root /tmp/os-installer

echo
echo 'Partitioning and mounting completed.'

exit 0
