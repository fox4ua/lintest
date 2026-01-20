chmod +x ./debootstrap-install.sh
./debootstrap-install.sh --disk /dev/sda --hostname deb1 --release bookworm --iface ens3 --net dhcp --yes


./debootstrap-install.sh --disk /dev/sda --hostname deb1 --release bookworm --iface ens3 \
  --net static --ip 203.0.113.10/24 --gw 203.0.113.1 --dns "1.1.1.1 8.8.8.8" --yes

Без LVM:
./debootstrap-install.sh --disk /dev/sda --lvm-mode none --yes

Classic LVM (всё свободное под root LV):
./debootstrap-install.sh --disk /dev/sda --lvm-mode lvm --vg-name vg0 --lv-root-name root --lv-root-size 100%FREE --yes


Thin-LVM (thinpool 95%VG, root virtual size авто или указать):
./debootstrap-install.sh --disk /dev/sda --lvm-mode thin --thinpool-size 95%VG --thin-root-vsize 30G --yes







./debootstrap-install.sh --disk /dev/sda --lvm-mode thin --thinpool-size 95%VG --thin-root-vsize 30G --root-pass '12345678' --hostname deb1 --release bookworm --iface ens3 --net dhcp --yes
