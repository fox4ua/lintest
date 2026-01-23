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




--disk /dev/sdX — целевой диск (обязательный параметр).
--boot-mode auto|uefi|bios — режим загрузки.

    --lvm-mode none|lvm|thin — режим хранения (без LVM / classic LVM / thin LVM).
    --vg-name vg0 — имя volume group для LVM.
    --thinpool-name
    --thinpool-pct-free 90 — процент свободного места под thinpool (по умолчанию 90%).
    --root-fs ext4|xfs|btrfs — ФС для root.
    --boot-size 256M|512M|1G|2G — размер /boot (если не указан, скрипт попросит).
    --swap none|1G|2G|4G — размер swap или none。
    --root-size 30G — размер root‑раздела/тома.
    --data-fs ext4|xfs|btrfs — ФС для data‑раздела.




--release bullseye|bookworm|trixie|testing|sid — релиз Debian.
--mirror http://deb.debian.org/debian — зеркало Debian.




    --hostname myhost — имя хоста.
    --hosts myhost.exemple.com — имя хоста.


    --iface ens3 — сетевой интерфейс.

    --net dhcp|static — режим сети.

    --ip 203.0.113.10/24 — IP для static‑режима.
    --gw 203.0.113.1 — шлюз для static‑режима.
    --dns "1.1.1.1 8.8.8.8" — DNS‑серверы.
    --networkd 0|1 — использовать systemd-networkd (1) или ifupdown (0).
    --root-pass 'StrongPass' — пароль root (если не указан, будет запрос; пустое значение блокирует root).
    --ssh-key-file /path/to/key — публичный ключ для root.
    --timezone Europe/Kyiv — таймзона.
    --yes — авто‑подтверждение разрушительных операций.








