chmod +x ./debootstrap-install.sh
./debootstrap-install.sh --disk /dev/sda --hostname deb1 --release bookworm --iface ens3 --net dhcp --yes


./debootstrap-install.sh --disk /dev/sda --hostname deb1 --release bookworm --iface ens3 \
  --net static --ip 203.0.113.10/24 --gw 203.0.113.1 --dns "1.1.1.1 8.8.8.8" --yes

