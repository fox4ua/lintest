#!/usr/bin/env bash
# shellcheck shell=bash

# Interactive prompts (terminal-based).
# These functions set variables in the caller scope:
#   ROOT_PASS, LVM_MODE, BOOT_SIZE, SWAP_CHOICE

prompt_root_pass() {
  local p1 p2
  while true; do
    echo -n "Enter root password (leave empty to LOCK root): " >&2
    IFS= read -r -s p1; echo >&2
    if [[ -z "$p1" ]]; then
      ROOT_PASS=""
      return 0
    fi
    echo -n "Confirm root password: " >&2
    IFS= read -r -s p2; echo >&2
    [[ "$p1" == "$p2" ]] || { echo "Passwords do not match. Try again." >&2; continue; }
    ROOT_PASS="$p1"
    return 0
  done
}


prompt_lvm_mode() {
  local ans
  while true; do
    echo "Select storage mode:"
    echo "  1) без LVM"
    echo "  2) classic LVM"
    echo "  3) тонкий LVM (thin)"
    read -r -p "Choose [1-3]: " ans
    case "$ans" in
      1) LVM_MODE="none"; return 0;;
      2) LVM_MODE="lvm";  return 0;;
      3) LVM_MODE="thin"; return 0;;
      *) echo "Invalid choice. Try again." >&2;;
    esac
  done
}


prompt_boot_size() {
  local ans
  while true; do
    echo "Select /boot size:"
    echo "  1) 256M"
    echo "  2) 512M"
    echo "  3) 1G"
    echo "  4) 2G"
    read -r -p "Choose [1-4]: " ans
    case "$ans" in
      1) BOOT_SIZE="256M"; return 0;;
      2) BOOT_SIZE="512M"; return 0;;
      3) BOOT_SIZE="1G";   return 0;;
      4) BOOT_SIZE="2G";   return 0;;
      *) echo "Invalid choice. Try again." >&2;;
    esac
  done
}


prompt_swap_choice() {
  local ans
  while true; do
    echo "Select swap:"
    echo "  1) без swap"
    echo "  2) 1G"
    echo "  3) 2G"
    echo "  4) 4G"
    read -r -p "Choose [1-4]: " ans
    case "$ans" in
      1) SWAP_CHOICE="none"; return 0;;
      2) SWAP_CHOICE="1G";   return 0;;
      3) SWAP_CHOICE="2G";   return 0;;
      4) SWAP_CHOICE="4G";   return 0;;
      *) echo "Invalid choice. Try again." >&2;;
    esac
  done
}

