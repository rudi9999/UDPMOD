#!/usr/bin/env bash
#
# Try `install_agnudp.sh --help` for usage.
#
# (c) 2023 Khaled AGN
#

set -e

###
# SCRIPT CONFIGURATION
###

# =============================================================

BINARY_URL="https://github.com/rudi9999/UDPMOD/raw/main"

# Domain Name
#DOMAIN="tu dominio aqui"

# OBFS, CAPA EXTRA DE SIFRADO DE PUNTO A PUNTO
OBFS=$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 8)

# =============================================================

# UDP PORT
UDP_PORT=":36712"

# MODO DE AUTENTICACION, SYSTEM PARA USAR LOS USUARIOS DE SISTEMA
MODE="system"
#MODE="passwords"
#MODE="external"

# PROTOCOL
PROTOCOL="udp"

# PASSWORDS
PASSWORD=""

# Basename of this script
SCRIPT_NAME="$(basename "$0")"

# Command line arguments of this script
SCRIPT_ARGS=("$@")

# Path for installing executable
EXECUTABLE_INSTALL_PATH="/usr/local/bin/udpmod"

# Paths to install systemd files
SYSTEMD_SERVICES_DIR="/etc/systemd/system"

# Directory to store udpmod config file
CONFIG_DIR="/etc/udpmod"

# URLs of GitHub
REPO_URL="https://github.com/apernet/udpmod"
API_BASE_URL="$BINARY_URL"

# curl command line flags.
# To using a proxy, please specify ALL_PROXY in the environ variable, such like:
# export ALL_PROXY=socks5h://192.0.2.1:1080
CURL_FLAGS=(-L -f -q --retry 5 --retry-delay 10 --retry-max-time 60)


###
# AUTO DETECTED GLOBAL VARIABLE
###

# Package manager
PACKAGE_MANAGEMENT_INSTALL="${PACKAGE_MANAGEMENT_INSTALL:-}"

# Operating System of current machine, supported: linux
OPERATING_SYSTEM="${OPERATING_SYSTEM:-}"

# Architecture of current machine, supported: 386, amd64, arm, arm64, mipsle, s390x
ARCHITECTURE="${ARCHITECTURE:-}"

# User for running udpmod
UDPMOD_USER="${UDPMOD_USER:-}"

# Directory for ACME certificates storage
UDPMOD_HOME_DIR="${UDPMOD_HOME_DIR:-}"


###
# ARGUMENTS
###

# Supported operation: install, remove, check_update
OPERATION=

# User specified version to install
VERSION=

# Force install even if installed
FORCE=

# User specified binary to install
LOCAL_FILE=


###
# COMMAND REPLACEMENT & UTILITIES
###

has_command() {
	local _command=$1
	
	type -P "$_command" > /dev/null 2>&1
}

curl() {
	command curl "${CURL_FLAGS[@]}" "$@"
}

mktemp() {
	command mktemp "$@" "hyservinst.XXXXXXXXXX"
}

tput() {
	if has_command tput; then
		command tput "$@"
		fi
}

tred() {
	tput setaf 1
}

tgreen() {
	tput setaf 2
}

tyellow() {
	tput setaf 3
}

tblue() {
	tput setaf 4
}

taoi() {
	tput setaf 6
}

tbold() {
	tput bold
}

treset() {
	tput sgr0
}

note() {
	local _msg="$1"
	
	echo -e "$SCRIPT_NAME: $(tbold)note: $_msg$(treset)"
}

warning() {
	local _msg="$1"
	
	echo -e "$SCRIPT_NAME: $(tyellow)warning: $_msg$(treset)"
}

error() {
	local _msg="$1"
	
	echo -e "$SCRIPT_NAME: $(tred)error: $_msg$(treset)"
}

has_prefix() {
	local _s="$1"
	local _prefix="$2"
	
	if [[ -z "$_prefix" ]]; then
		return 0
		fi
		
		if [[ -z "$_s" ]]; then
			return 1
			fi
			
			[[ "x$_s" != "x${_s#"$_prefix"}" ]]
}

systemctl() {
	if [[ "x$FORCE_NO_SYSTEMD" == "x2" ]] || ! has_command systemctl; then
		return
		fi
		
		command systemctl "$@"
}

show_argument_error_and_exit() {
	local _error_msg="$1"
	
	error "$_error_msg"
	echo "Try \"$0 --help\" for the usage." >&2
	exit 22
}

install_content() {
	local _install_flags="$1"
	local _content="$2"
	local _destination="$3"
	
	local _tmpfile="$(mktemp)"
	
	echo -ne "Install $_destination ... "
	echo "$_content" > "$_tmpfile"
	if install "$_install_flags" "$_tmpfile" "$_destination"; then
		echo -e "ok"
		fi
		
		rm -f "$_tmpfile"
}

remove_file() {
	local _target="$1"
	
	echo -ne "Remove $_target ... "
	if rm "$_target"; then
		echo -e "ok"
		fi
}

exec_sudo() {
	# exec sudo with configurable environ preserved.
	local _saved_ifs="$IFS"
	IFS=$'\n'
	local _preserved_env=(
		$(env | grep "^PACKAGE_MANAGEMENT_INSTALL=" || true)
		$(env | grep "^OPERATING_SYSTEM=" || true)
		$(env | grep "^ARCHITECTURE=" || true)
		$(env | grep "^UDPMOD_\w*=" || true)
		$(env | grep "^FORCE_\w*=" || true)
	)
	IFS="$_saved_ifs"
	
	exec sudo env \
	"${_preserved_env[@]}" \
	"$@"
}

detect_package_manager() {
	if [[ -n "$PACKAGE_MANAGEMENT_INSTALL" ]]; then
		return 0
		fi
		
		if has_command apt; then
			PACKAGE_MANAGEMENT_INSTALL='apt update; apt -y install'
			return 0
			fi
			
			if has_command dnf; then
				PACKAGE_MANAGEMENT_INSTALL='dnf check-update; dnf -y install'
				return 0
				fi
				
				if has_command yum; then
					PACKAGE_MANAGEMENT_INSTALL='yum update; yum -y install'
					return 0
					fi
					
					if has_command zypper; then
						PACKAGE_MANAGEMENT_INSTALL='zypper update; zypper install -y --no-recommends'
						return 0
						fi
						
						if has_command pacman; then
							PACKAGE_MANAGEMENT_INSTALL='pacman -Syu; pacman -Syu --noconfirm'
							return 0
							fi
							
							return 1
}

install_software() {
	local _package_name="$1"
	
	if ! detect_package_manager; then
		error "Supported package manager is not detected, please install the following package manually:"
		echo
		echo -e "\t* $_package_name"
		echo
		exit 65
		fi
		
		echo "Installing missing dependence '$_package_name' with '$PACKAGE_MANAGEMENT_INSTALL' ... "
		if $PACKAGE_MANAGEMENT_INSTALL "$_package_name"; then
			echo "ok"
			else
				error "Cannot install '$_package_name' with detected package manager, please install it manually."
				exit 65
				fi
}

is_user_exists() {
	local _user="$1"
	
	id "$_user" > /dev/null 2>&1
}

check_permission() {
	if [[ "$UID" -eq '0' ]]; then
		return
		fi
		
		note "The user currently executing this script is not root."
		
		case "$FORCE_NO_ROOT" in
		'1')
		warning "FORCE_NO_ROOT=1 is specified, we will process without root and you may encounter the insufficient privilege error."
		;;
	*)
	if has_command sudo; then
		note "Re-running this script with sudo, you can also specify FORCE_NO_ROOT=1 to force this script running with current user."
		exec_sudo "$0" "${SCRIPT_ARGS[@]}"
		else
			error "Please run this script with root or specify FORCE_NO_ROOT=1 to force this script running with current user."
			exit 13
			fi
			;;
		esac
}

check_environment_operating_system() {
	if [[ -n "$OPERATING_SYSTEM" ]]; then
		warning "OPERATING_SYSTEM=$OPERATING_SYSTEM is specified, opreating system detection will not be perform."
		return
		fi
		
		if [[ "x$(uname)" == "xLinux" ]]; then
			OPERATING_SYSTEM=linux
			return
			fi
			
			error "This script only supports Linux."
			note "Specify OPERATING_SYSTEM=[linux|darwin|freebsd|windows] to bypass this check and force this script running on this $(uname)."
			exit 95
}

check_environment_architecture() {
	if [[ -n "$ARCHITECTURE" ]]; then
		warning "ARCHITECTURE=$ARCHITECTURE is specified, architecture detection will not be performed."
		return
		fi
		
		case "$(uname -m)" in
	'amd64' | 'x86_64')
	ARCHITECTURE='amd64'
	;;
	'armv8' | 'aarch64')
	ARCHITECTURE='arm64'
	;;
	*)
	error "The architecture '$(uname -a)' is not supported."
	note "Specify ARCHITECTURE=<architecture> to bypass this check and force this script running on this $(uname -m)."
	exit 8
	;;
	esac
}

check_environment_systemd() {
	if [[ -d "/run/systemd/system" ]] || grep -q systemd <(ls -l /sbin/init); then
		return
		fi
		
		case "$FORCE_NO_SYSTEMD" in
		'1')
		warning "FORCE_NO_SYSTEMD=1 is specified, we will process as normal even if systemd is not detected by us."
		;;
	'2')
	warning "FORCE_NO_SYSTEMD=2 is specified, we will process but all systemd related command will not be executed."
	;;
	*)
	error "This script only supports Linux distributions with systemd."
	note "Specify FORCE_NO_SYSTEMD=1 to disable this check and force this script running as systemd is detected."
	note "Specify FORCE_NO_SYSTEMD=2 to disable this check along with all systemd related commands."
	;;
	esac
}

check_environment_curl() {
	if has_command curl; then
		return
		fi
		apt update; apt -y install curl
}

check_environment_grep() {
	if has_command grep; then
		return
		fi
		apt update; apt -y install grep
}

check_environment() {
	check_environment_operating_system
	check_environment_architecture
	check_environment_systemd
	check_environment_curl
	check_environment_grep
}

vercmp_segment() {
	local _lhs="$1"
	local _rhs="$2"
	
	if [[ "x$_lhs" == "x$_rhs" ]]; then
		echo 0
		return
		fi
		if [[ -z "$_lhs" ]]; then
			echo -1
			return
			fi
			if [[ -z "$_rhs" ]]; then
				echo 1
				return
				fi
				
				local _lhs_num="${_lhs//[A-Za-z]*/}"
				local _rhs_num="${_rhs//[A-Za-z]*/}"
				
				if [[ "x$_lhs_num" == "x$_rhs_num" ]]; then
					echo 0
					return
					fi
					if [[ -z "$_lhs_num" ]]; then
						echo -1
						return
						fi
						if [[ -z "$_rhs_num" ]]; then
							echo 1
							return
							fi
							local _numcmp=$(($_lhs_num - $_rhs_num))
							if [[ "$_numcmp" -ne 0 ]]; then
								echo "$_numcmp"
								return
								fi
								
								local _lhs_suffix="${_lhs#"$_lhs_num"}"
								local _rhs_suffix="${_rhs#"$_rhs_num"}"
								
								if [[ "x$_lhs_suffix" == "x$_rhs_suffix" ]]; then
									echo 0
									return
									fi
									if [[ -z "$_lhs_suffix" ]]; then
										echo 1
										return
										fi
										if [[ -z "$_rhs_suffix" ]]; then
											echo -1
											return
											fi
											if [[ "$_lhs_suffix" < "$_rhs_suffix" ]]; then
												echo -1
												return
												fi
												echo 1
}

vercmp() {
	local _lhs=${1#v}
	local _rhs=${2#v}
	
	while [[ -n "$_lhs" && -n "$_rhs" ]]; do
		local _clhs="${_lhs/.*/}"
		local _crhs="${_rhs/.*/}"
		
		local _segcmp="$(vercmp_segment "$_clhs" "$_crhs")"
		if [[ "$_segcmp" -ne 0 ]]; then
			echo "$_segcmp"
			return
			fi
			
			_lhs="${_lhs#"$_clhs"}"
			_lhs="${_lhs#.}"
			_rhs="${_rhs#"$_crhs"}"
			_rhs="${_rhs#.}"
			done
			
			if [[ "x$_lhs" == "x$_rhs" ]]; then
				echo 0
				return
				fi
				
				if [[ -z "$_lhs" ]]; then
					echo -1
					return
					fi
					
					if [[ -z "$_rhs" ]]; then
						echo 1
						return
						fi
						
						return
}

check_udpmod_user() {
	local _default_udpmod_user="$1"
	
	if [[ -n "$UDPMOD_USER" ]]; then
		return
		fi
		
		if [[ ! -e "$SYSTEMD_SERVICES_DIR/udpmod-server.service" ]]; then
			UDPMOD_USER="$_default_udpmod_user"
			return
			fi
			
			UDPMOD_USER="$(grep -o '^User=\w*' "$SYSTEMD_SERVICES_DIR/udpmod-server.service" | tail -1 | cut -d '=' -f 2 || true)"
			
			if [[ -z "$UDPMOD_USER" ]]; then
				UDPMOD_USER="$_default_udpmod_user"
				fi
}

check_udpmod_homedir() {
	local _default_udpmod_homedir="$1"
	
	if [[ -n "$UDPMOD_HOME_DIR" ]]; then
		return
		fi
		
		if ! is_user_exists "$UDPMOD_USER"; then
			UDPMOD_HOME_DIR="$_default_udpmod_homedir"
			return
			fi
			
			UDPMOD_HOME_DIR="$(eval echo ~"$UDPMOD_USER")"
}


###
# ARGUMENTS PARSER
###

show_usage_and_exit() {
	echo
	echo -e "\t$(tbold)$SCRIPT_NAME$(treset) - Rufu99-UDP server install script"
	echo
	echo -e "Usage:"
	echo
	echo -e "$(tbold)Install Rufu99-UDP$(treset)"
	echo -e "\t$0 [ -f | -l <file> | --version <version> ]"
	echo -e "Flags:"
	echo -e "\t-f, --force\tForce re-install latest or specified version even if it has been installed."
	echo -e "\t-l, --local <file>\tInstall specified AGN-UDP binary instead of download it."
	echo -e "\t--version <version>\tInstall specified version instead of the latest."
	echo
	echo -e "$(tbold)Remove Rufu99-UDP$(treset)"
	echo -e "\t$0 --remove"
	echo
	echo -e "$(tbold)Check for the update$(treset)"
	echo -e "\t$0 -c"
	echo -e "\t$0 --check"
	echo
	echo -e "$(tbold)Show this help$(treset)"
	echo -e "\t$0 -h"
	echo -e "\t$0 --help"
	exit 0
}

parse_arguments() {
	while [[ "$#" -gt '0' ]]; do
		case "$1" in
		'--remove')
		if [[ -n "$OPERATION" && "$OPERATION" != 'remove' ]]; then
			show_argument_error_and_exit "Option '--remove' is conflicted with other options."
			fi
			OPERATION='remove'
			;;
		'--version')
		VERSION="$2"
		if [[ -z "$VERSION" ]]; then
			show_argument_error_and_exit "Please specify the version for option '--version'."
			fi
			shift
			if ! has_prefix "$VERSION" 'v'; then
				show_argument_error_and_exit "Version numbers should begin with 'v' (such like 'v1.3.1'), got '$VERSION'"
				fi
				;;
			'-c' | '--check')
			if [[ -n "$OPERATION" && "$OPERATION" != 'check' ]]; then
				show_argument_error_and_exit "Option '-c' or '--check' is conflicted with other option."
				fi
				OPERATION='check_update'
				;;
			'-f' | '--force')
			FORCE='1'
			;;
			'-h' | '--help')
			show_usage_and_exit
			;;
			'-l' | '--local')
			LOCAL_FILE="$2"
			if [[ -z "$LOCAL_FILE" ]]; then
				show_argument_error_and_exit "Please specify the local binary to install for option '-l' or '--local'."
				fi
				break
				;;
			*)
			show_argument_error_and_exit "Unknown option '$1'"
			;;
			esac
			shift
			done
			
			if [[ -z "$OPERATION" ]]; then
				OPERATION='install'
				fi
				
				# validate arguments
				case "$OPERATION" in
				'install')
				if [[ -n "$VERSION" && -n "$LOCAL_FILE" ]]; then
					show_argument_error_and_exit '--version and --local cannot be specified together.'
					fi
					;;
				*)
				if [[ -n "$VERSION" ]]; then
					show_argument_error_and_exit "--version is only avaiable when install."
					fi
					if [[ -n "$LOCAL_FILE" ]]; then
						show_argument_error_and_exit "--local is only avaiable when install."
						fi
						;;
					esac
}


###
# FILE TEMPLATES
###

# /etc/systemd/system/udpmod-server.service
tpl_udpmod_server_service_base() {
  local _config_name="$1"

  cat << EOF
[Unit]
Description=UDPMOD Service BY @Rufu99
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=/etc/udpmod
Environment="PATH=/usr/local/bin/udpmod:/usr/bin"
ExecStart=/usr/local/bin/udpmod -config /etc/udpmod/config.json server

[Install]
WantedBy=multi-user.target
EOF
}

# /etc/systemd/system/udpmod-server.service
tpl_udpmod_server_service() {
  tpl_udpmod_server_service_base 'config'
}

# /etc/systemd/system/udpmod-server@.service
tpl_udpmod_server_x_service() {
  tpl_udpmod_server_service_base '%i'
}

# /etc/udpmod/config.json
tpl_etc_udpmod_config_json() {
  cat << EOF
{
  "listen": "$UDP_PORT",
  "protocol": "$PROTOCOL",
  "cert": "/etc/udpmod/udpmod.server.crt",
  "key": "/etc/udpmod/udpmod.server.key",
  "up": "100 Mbps",
  "up_mbps": 100,
  "down": "100 Mbps",
  "down_mbps": 100,
  "disable_udp": false,
  "obfs": "$OBFS",
  "auth": {
	"mode": "$MODE",
	"config": ["$PASSWORD"]
         }
}
EOF
}


###
# SYSTEMD
###

get_running_services() {
	if [[ "x$FORCE_NO_SYSTEMD" == "x2" ]]; then
		return
		fi
		
		systemctl list-units --state=active --plain --no-legend \
		| grep -o "udpmod-server@*[^\s]*.service" || true
}

restart_running_services() {
	if [[ "x$FORCE_NO_SYSTEMD" == "x2" ]]; then
		return
		fi
		
		echo "Restarting running service ... "
		
		for service in $(get_running_services); do
			echo -ne "Restarting $service ... "
			systemctl restart "$service"
			echo "done"
			done
}

stop_running_services() {
	if [[ "x$FORCE_NO_SYSTEMD" == "x2" ]]; then
		return
		fi
		
		echo "Stopping running service ... "
		
		for service in $(get_running_services); do
			echo -ne "Stopping $service ... "
			systemctl stop "$service"
			echo "done"
			done
}


###
# UDPMOD & GITHUB API
###

is_udpmod_installed() {
	# RETURN VALUE
	# 0: udpmod is installed
	# 1: udpmod is not installed
	
	if [[ -f "$EXECUTABLE_INSTALL_PATH" || -h "$EXECUTABLE_INSTALL_PATH" ]]; then
		return 0
	fi
		return 1
}

get_installed_version() {
	if is_udpmod_installed; then
		"$EXECUTABLE_INSTALL_PATH" -v | grep -v MOD | cut -d ' ' -f3|tr -d '\n'
	fi
}

get_latest_version() {
	if [[ -n "$VERSION" ]]; then
		echo "$VERSION"
		return
	fi
	
	local _tmpfile=$(mktemp)
	if ! curl -sS -H 'Accept: application/vnd.github.v3+json' "$API_BASE_URL/version" -o "$_tmpfile"; then
		error "Failed to get latest release, please check your network."
		exit 11
	fi
			
	local _latest_version=$(cat "$_tmpfile"|tr -d '\n')
	_latest_version=${_latest_version#'"'}
	_latest_version=${_latest_version%'"'}
	
	if [[ -n "$_latest_version" ]]; then
		echo "$_latest_version"
	fi
		
	rm -rf "$_tmpfile"
}

download_udpmod() {
	local _version="$1"
	local _destination="$2"
	
	#local _download_url="$REPO_URL/releases/download/$_version/udpmod-$OPERATING_SYSTEM-$ARCHITECTURE"
	local _download_url="$BINARY_URL/udpmod-$ARCHITECTURE"
	echo "Downloading udpmod archive: $_download_url ..."
	if ! curl -R -H 'Cache-Control: no-cache' "$_download_url" -o "$_destination"; then
		error "Download failed! Please check your network and try again."
		return 11
		fi
		return 0
}

check_update() {
	# RETURN VALUE
	# 0: update available
	# 1: installed version is latest
	
	echo -ne "Checking for installed version ... "
	local _installed_version="$(get_installed_version)"
	if [[ -n "$_installed_version" ]]; then
		echo "$_installed_version"
	else
		echo "not installed"
	fi
			
	echo -ne "Checking for latest version ... "
	local _latest_version="$(get_latest_version)"
	if [[ -n "$_latest_version" ]]; then
		echo "$_latest_version"
		VERSION="$_latest_version"
	else
		echo "failed"
		return 1
	fi
					
	local _vercmp="$(vercmp "$_installed_version" "$_latest_version")"
	if [[ "$_vercmp" -lt 0 ]]; then
		return 0
	fi
		
	return 1
}


###
# ENTRY
###

perform_install_udpmod_binary() {
	if [[ -n "$LOCAL_FILE" ]]; then
		note "Performing local install: $LOCAL_FILE"
		
		echo -ne "Installing udpmod executable ... "
		
		if install -Dm755 "$LOCAL_FILE" "$EXECUTABLE_INSTALL_PATH"; then
			echo "ok"
		else
			exit 2
		fi
				
		return
	fi
				
	local _tmpfile=$(mktemp)
				
	if ! download_udpmod "$VERSION" "$_tmpfile"; then
		rm -f "$_tmpfile"
		exit 11
	fi
					
	echo -ne "Installing udpmod executable ... "
					
	if install -Dm755 "$_tmpfile" "$EXECUTABLE_INSTALL_PATH"; then
		echo "ok"
	else
		exit 13
	fi
							
	rm -f "$_tmpfile"
}

perform_remove_udpmod_binary() {
	remove_file "$EXECUTABLE_INSTALL_PATH"
}

perform_install_udpmod_example_config() {
	if [[ ! -d "$CONFIG_DIR" ]]; then
		install_content -Dm644 "$(tpl_etc_udpmod_config_json)" "$CONFIG_DIR/config.json"
		fi
}

perform_install_udpmod_systemd() {
	if [[ "x$FORCE_NO_SYSTEMD" == "x2" ]]; then
		return
		fi
		
		install_content -Dm644 "$(tpl_udpmod_server_service)" "$SYSTEMD_SERVICES_DIR/udpmod-server.service"
		install_content -Dm644 "$(tpl_udpmod_server_x_service)" "$SYSTEMD_SERVICES_DIR/udpmod-server@.service"
		
		systemctl daemon-reload
}

perform_remove_udpmod_systemd() {
	remove_file "$SYSTEMD_SERVICES_DIR/udpmod-server.service"
	remove_file "$SYSTEMD_SERVICES_DIR/udpmod-server@.service"
	
	systemctl daemon-reload
}

perform_install_udpmod_home_legacy() {
	if ! is_user_exists "$UDPMOD_USER"; then
		echo -ne "Creating user $UDPMOD_USER ... "
		useradd -r -d "$UDPMOD_HOME_DIR" -m "$UDPMOD_USER"
		echo "ok"
		fi
}

inicio(){
	clear
	echo
	read -p ' INGRESA UN DOMINIO/HOST: ' DOMAIN
	echo
}

perform_install() {
	local _is_frash_install
	if ! is_udpmod_installed; then
		_is_frash_install=1
	fi
		
	local _is_update_required
		
	if [[ -n "$LOCAL_FILE" ]] || [[ -n "$VERSION" ]] || check_update; then
		_is_update_required=1
	fi
			
	if [[ "x$FORCE" == "x1" ]]; then
		if [[ -z "$_is_update_required" ]]; then
			note "Option '--force' is specified, re-install even if installed version is the latest."
		fi
			_is_update_required=1
	fi
					
	if [[ -z "$_is_update_required" ]]; then
		echo "$(tgreen)Installed version is up-to-dated, there is nothing to do.$(treset)"
		return
	fi
	inicio
	perform_install_udpmod_binary
	perform_install_udpmod_example_config
	perform_install_udpmod_home_legacy
	perform_install_udpmod_systemd
	setup_ssl
	start_services
	if [[ -n "$_is_frash_install" ]]; then
		D=$(cat $CONFIG_DIR/config.json|grep 'listen\|obfs'|sed 's/"\|,//g'|sed 's/: :/: /'|sed 's/listen/PUERTO/'|sed 's/obfs/OBFS/')
		echo
		echo -e "$(tbold)Congratulation! Rufu99-UDP has been successfully installed on your server.$(treset)"
		echo
		echo -e "$(tbold)Client app AGN INJECTOR:$(treset)"
		echo -e "$(tblue)https://play.google.com/store/apps/details?id=com.agn.injector$(treset)"
		echo
		echo "$D"
		echo
		echo "crear usuario manualmente"
		echo
		echo "useradd -M -s /bin/false NOMBRE; (echo 'CONTRA'; echo 'CONTRA')|passwd NOMBRE"
		echo
	else
		restart_running_services
		
		echo
		echo -e "$(tbold)Rufu99-UDP has been successfully update to $VERSION.$(treset)"
		echo
	fi
}

perform_remove() {
	perform_remove_udpmod_binary
	stop_running_services
	perform_remove_udpmod_systemd
	
	echo
	echo -e "$(tbold)Congratulation! Rufu99-UDP has been successfully removed from your server.$(treset)"
	echo
	echo -e "You still need to remove configuration files and ACME certificates manually with the following commands:"
	echo
	echo -e "\t$(tred)rm -rf "$CONFIG_DIR"$(treset)"
	if [[ "x$UDPMOD_USER" != "xroot" ]]; then
		echo -e "\t$(tred)userdel -r "$UDPMOD_USER"$(treset)"
		fi
		if [[ "x$FORCE_NO_SYSTEMD" != "x2" ]]; then
			echo
			echo -e "You still might need to disable all related systemd services with the following commands:"
			echo
			echo -e "\t$(tred)rm -f /etc/systemd/system/multi-user.target.wants/udpmod-server.service$(treset)"
			echo -e "\t$(tred)rm -f /etc/systemd/system/multi-user.target.wants/udpmod-server@*.service$(treset)"
			echo -e "\t$(tred)systemctl daemon-reload$(treset)"
			fi
			echo
}

perform_check_update() {
	if check_update; then
		echo
		echo -e "$(tbold)Update available: $VERSION$(treset)"
		echo
		echo -e "$(tgreen)You can download and install the latest version by execute this script without any arguments.$(treset)"
		echo
		else
			echo
			echo "$(tgreen)Installed version is up-to-dated.$(treset)"
			echo
			fi
}


setup_ssl() {
	echo "Installing ssl"
	
	openssl genrsa -out /etc/udpmod/udpmod.ca.key 2048
	
	openssl req -new -x509 -days 3650 -key /etc/udpmod/udpmod.ca.key -subj "/C=CN/ST=GD/L=SZ/O=Udpmod, Inc./CN=Udpmod Root CA" -out /etc/udpmod/udpmod.ca.crt
	
	openssl req -newkey rsa:2048 -nodes -keyout /etc/udpmod/udpmod.server.key -subj "/C=CN/ST=GD/L=SZ/O=Udpmod, Inc./CN=$DOMAIN" -out /etc/udpmod/udpmod.server.csr
	
	openssl x509 -req -extfile <(printf "subjectAltName=DNS:$DOMAIN,DNS:$DOMAIN") -days 3650 -in /etc/udpmod/udpmod.server.csr -CA /etc/udpmod/udpmod.ca.crt -CAkey /etc/udpmod/udpmod.ca.key -CAcreateserial -out /etc/udpmod/udpmod.server.crt	
}

start_services() {
	echo "Starting AGN-UDP"
	apt update
	sudo debconf-set-selections <<< "iptables-persistent iptables-persistent/autosave_v4 boolean true"
        sudo debconf-set-selections <<< "iptables-persistent iptables-persistent/autosave_v6 boolean true"
	apt -y install iptables-persistent
	iptables -t nat -A PREROUTING -i $(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1) -p udp --dport 10000:65000 -j DNAT --to-destination $UDP_PORT
	ip6tables -t nat -A PREROUTING -i $(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1) -p udp --dport 10000:65000 -j DNAT --to-destination $UDP_PORT
	sysctl net.ipv4.conf.all.rp_filter=0
	sysctl net.ipv4.conf.$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1).rp_filter=0 
	echo "net.ipv4.ip_forward = 1
	net.ipv4.conf.all.rp_filter=0
	net.ipv4.conf.$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1).rp_filter=0" > /etc/sysctl.conf  
	sysctl -p
        sudo iptables-save > /etc/iptables/rules.v4
        sudo ip6tables-save > /etc/iptables/rules.v6
	systemctl enable udpmod-server.service
	systemctl start udpmod-server.service	
}



main() {
	parse_arguments "$@"
	check_permission
	check_environment
	check_udpmod_user "udpmod"
	check_udpmod_homedir "/var/lib/$UDPMOD_USER"
	case "$OPERATION" in
			 "install") perform_install;;
				"remove") perform_remove;;
	"check_update") perform_check_update;;
							 *) error "Unknown operation '$OPERATION'.";;
	esac
}

main "$@"

# vim:set ft=bash ts=2 sw=2 sts=2 et:
