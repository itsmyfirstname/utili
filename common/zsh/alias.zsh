#! /usr/bin/zsh
NETWORK_NAME="Hey_Beaches"
onedotipv4="192.168.1.171 1.1.1.1 9.9.9.9"
network_uuid=""
net_device_uuid=""
if command -v nmcli >/dev/null 2>&1 && nmcli connection show 2>/dev/null | grep -q "$NETWORK_NAME"; then
  network_uuid="$(nmcli connection show | grep "$NETWORK_NAME" | awk '{print $2}')"
  net_device_uuid="$(nmcli connection show | grep "$NETWORK_NAME" | awk '{print $4}')"
fi


function qedit() {

	case $1 in
	  zsh)
		  nvim $HOME/.config/zsh/
		  ;;
	  zshrc)
		  nvim $HOME/.zshrc
		  ;;
	  nvim)
		  nvim $HOME/.config/nvim/init.lua
		  ;;

	  config | conf)
		  nvim $HOME/.config 
		  ;;
	  *)
		  echo "Availavle options: zsh | zshrc | config"
		  ;;
	esac
}

function qssh() {
	echo "connecting $@"
	kitty +kitten ssh $@
}


function flash-usb() {
	source_iso=${1:-""}
	mount_device=${2:-"/dev/sda"}

	if [[ -z $source_iso ]]; then
		echo "Need source ISO"
		return
	fi

	echo "Source: ${source_iso}"
	echo "Mounted Device: ${mount_device}"
	echo "Everything look good?"
	read continue_flash
	if [[ "$continue_flash" == "y" || "$continue_flash" == "Y" ]]; then
		echo "Proceeding: $continue_flash"
		sudo dd bs=4M if=$source_iso of=$mount_device status=progress oflag=sync
	fi
	echo "Exiting..."

}

# function lazygit() {
# 	case $1 in 
# 		show-remote) # Show remotes
# 			git remote -v
# 			;;
# 		undo-commit)
# 			git reset --soft HEAD~1
# 			;;
# 		push) # Assume we just want to commit and push some changes
# 			git add . && git commit -m "$1" && git push
# 			;;
# 		*)
# 			echo "push | show-remote | undo-commit"
# 	esac
# }

function lazynet() {
	case $1 in
		show) # Show available networks
			nmcli dev wifi list
			;;
		connect)
			nmcli dev wifi connect $2 -a
			;;
		*)
			echo "Available options: show | connect"
			printf "example: lazynet connect myNetwork"
			nmcli --help
			;;
	esac
}

if [[ -r /etc/arch-release ]] && command -v pacman >/dev/null 2>&1; then
  alias archer-refresh-keyring="sudo pacman -Sy archlinux-keyring"
  alias archer-full-upgrade="archer-refresh-keyring && sudo pacman -Syu" # Full System Upgrade, prepare your...evening, could get messy
  alias archer-refresh-package-lists="archer-refresh-keyring && sudo pacman -Syyu"
fi


if [[ -n $network_uuid && -n $net_device_uuid ]]; then
  alias dns-set-custom="nmcli con show ${network_uuid} | grep ipv | grep .dns  && sudo nmcli con mod ${network_uuid} ipv4.dns '$onedotipv4' ipv4.ignore-auto-dns yes && sudo nmcli connection modify ${network_uuid} connection.dns-over-tls 1 && sudo nmcli general reload dns-full && sudo nmcli dev reapply ${net_device_uuid} && nmcli con show ${network_uuid} | grep ipv | grep .dns  && nslookup google.com "

  alias dns-set-default="nmcli con show ${network_uuid} | grep ipv | grep .dns  && nmcli con mod ${network_uuid} ipv4.dns '' ipv4.ignore-auto-dns no ipv6.dns '' ipv6.ignore-auto-dns no connection.dns-over-tls 0 && nmcli general reload dns-full && nmcli dev reapply ${net_device_uuid} && nmcli con show ${network_uuid} | grep ipv | grep .dns && nslookup google.com "
  alias dns-test="nmcli con show ${network_uuid} | grep ipv | grep .dns && nslookup google.com "
fi

alias dot-venv-activate="source .venv/bin/activate"
alias dot-ssh-seedbox="qssh mehays@192.168.1.148"
alias dot-tmux="tmux new-session -A -s main"
alias dot-ls-local-ports="sudo ss -tulpn"
alias dot-mount-nas='sudo mount -t nfs 192.168.1.190:/mnt/atlas/video ~/nas/'
