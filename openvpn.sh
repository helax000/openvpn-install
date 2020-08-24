#!/bin/bash
#
# https://github.com/Nyr/openvpn-install
#
# Copyright (c) 2013 Nyr. Released under the MIT License.

# defined some common variables
server_config_file="/etc/openvpn/server/server.conf"
openvpn_log_file="/etc/openvpn/server/openvpn.log"
password_log_file="/etc/openvpn/server/openvpn-password.log"
password_file="/etc/openvpn/psw-file"
Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]:${Font_color_suffix}"
Error="${Red_font_prefix}[错误]:${Font_color_suffix}"
Tip="${Green_font_prefix}[注意]:${Font_color_suffix}"
Separator_1="——————————————————————————————"
# Detect Debian users running the script with "sh" instead of bash
if readlink /proc/$$/exe | grep -q "dash"; then
	echo 'This installer needs to be run with "bash", not "sh".' && exit 1
fi

# Discard stdin. Needed when running from an one-liner which includes a newline
read -N 999999 -t 0.001

# Detect OpenVZ 6
if [[ $(uname -r | cut -d "." -f 1) -eq 2 ]]; then
	echo "The system is running an old kernel, which is incompatible with this installer." && exit 1
fi

# Detect OS
# $os_version variables aren't always in use, but are kept here for convenience
if grep -qs "ubuntu" /etc/os-release; then
	os="ubuntu"
	os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2 | tr -d '.')
	group_name="nogroup"
elif [[ -e /etc/debian_version ]]; then
	os="debian"
	os_version=$(grep -oE '[0-9]+' /etc/debian_version | head -1)
	group_name="nogroup"
elif [[ -e /etc/centos-release ]]; then
	os="centos"
	os_version=$(grep -oE '[0-9]+' /etc/centos-release | head -1)
	group_name="nobody"
elif [[ -e /etc/fedora-release ]]; then
	os="fedora"
	os_version=$(grep -oE '[0-9]+' /etc/fedora-release | head -1)
	group_name="nobody"
else
	echo -e "This installer seems to be running on an unsupported distribution.\nSupported distributions are Ubuntu, Debian, CentOS, and Fedora." && exit 1
fi

if [[ "$os" == "ubuntu" && "$os_version" -lt 1804 ]]; then
	echo -e "Ubuntu 18.04 or higher is required to use this installer.\nThis version of Ubuntu is too old and unsupported." && exit 1
fi

if [[ "$os" == "debian" && "$os_version" -lt 9 ]]; then
	echo -e "Debian 9 or higher is required to use this installer.\nThis version of Debian is too old and unsupported." && exit 1
fi

if [[ "$os" == "centos" && "$os_version" -lt 7 ]]; then
	echo -e "CentOS 7 or higher is required to use this installer.\nThis version of CentOS is too old and unsupported." && exit 1
fi

# Detect environments where $PATH does not include the sbin directories
if ! grep -q sbin <<< "$PATH"; then
	echo '$PATH does not include sbin. Try using "su -" instead of "su".' && exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
	echo "This installer needs to be run with superuser privileges." && exit 1
fi

if [[ ! -e /dev/net/tun ]] || ! ( exec 7<>/dev/net/tun ) 2>/dev/null; then
	echo -e "The system does not have the TUN device available.\nTUN needs to be enabled before running this installer." && exit 1
fi

# 显示 菜单状态
menu_status(){
    echo
	if [[ -e ${server_config_file} ]]; then
		check_pid
		if [[ ! -z "${PID}" ]]; then
			echo -e " 当前状态: ${Green_font_prefix}已安装 openVPN${Font_color_suffix} 并 ${Green_font_prefix}已启动${Font_color_suffix}"
		else
			echo -e " 当前状态: ${Green_font_prefix}已安装 openVPN${Font_color_suffix} 但 ${Red_font_prefix}未启动${Font_color_suffix}"
		fi
		now_mode=$(cat "${server_config_file}"|grep "^auth-user-pass-verify")
		if [[ -z "${now_mode}" ]]; then
			echo -e " 当前用户验证方式: ${Green_font_prefix}证书${Font_color_suffix}" && echo
		else
			echo -e " 当前用户验证方式: ${Green_font_prefix}证书+账号${Font_color_suffix}" && echo
		fi
	else
		echo -e " ${Info}当前状态: ${Red_font_prefix}未安装 openVPN${Font_color_suffix}" && echo
	fi
}

check_username(){
    if [[ ! -z "$client_username" ]] ; then
        if [[ -z "`grep "^${client_username}" /etc/openvpn/psw-file `" ]]; then
            username_flag=1
            return
        else
            echo "[${client_username}], username Already exists"
        fi
    else
        echo "[${client_username}], username can't be null"
    fi
    username_flag=0
}

new_client () {
	# Generates the custom client.ovpn
	{
	cat /etc/openvpn/server/client-common.txt
	echo "<ca>"
	cat /etc/openvpn/server/easy-rsa/pki/ca.crt
	echo "</ca>"
	echo "<cert>"
	sed -ne '/BEGIN CERTIFICATE/,$ p' /etc/openvpn/server/easy-rsa/pki/issued/"$client".crt
	echo "</cert>"
	echo "<key>"
	cat /etc/openvpn/server/easy-rsa/pki/private/"$client".key
	echo "</key>"
	echo "<tls-crypt>"
	sed -ne '/BEGIN OpenVPN Static key/,$ p' /etc/openvpn/server/tc.key
	echo "</tls-crypt>"
	} > /etc/openvpn/client/"$client".ovpn
}

Install_OpenVPN(){
    check_OpenVPN
    [[ $? -eq 0 ]] && menu_status && return 1
    clear
    echo 'Welcome to this OpenVPN road warrior installer!'
    # If system has a single IPv4, it is selected automatically. Else, ask the user
    if [[ $(ip -4 addr | grep inet | grep -vEc '127(\.[0-9]{1,3}){3}') -eq 1 ]]; then
        ip=$(ip -4 addr | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' | cut -d '/' -f 1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}')
    else
        number_of_ip=$(ip -4 addr | grep inet | grep -vEc '127(\.[0-9]{1,3}){3}')
        echo
        echo "Which IPv4 address should be used?"
        ip -4 addr | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' | cut -d '/' -f 1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | nl -s ') '
        read -e -p "IPv4 address [1]: " ip_number
        until [[ -z "$ip_number" || "$ip_number" =~ ^[0-9]+$ && "$ip_number" -le "$number_of_ip" ]]; do
            echo "$ip_number: invalid selection."
            read -e -p "IPv4 address [1]: " ip_number
        done
        [[ -z "$ip_number" ]] && ip_number="1"
        ip=$(ip -4 addr | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' | cut -d '/' -f 1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | sed -n "$ip_number"p)
    fi
    # If $ip is a private IP address, the server must be behind NAT
    if echo "$ip" | grep -qE '^(10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168)'; then
        echo
        echo "This server is behind NAT. What is the public IPv4 address or hostname?"
        # Get public IP and sanitize with grep
        get_public_ip=$(grep -m 1 -oE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' <<< "$(wget -T 10 -t 1 -4qO- "http://ip1.dynupdate.no-ip.com/" || curl -m 10 -4Ls "http://ip1.dynupdate.no-ip.com/")")
        read -e -p "Public IPv4 address / hostname [$get_public_ip]: " public_ip
        # If the checkip service is unavailable and user didn't provide input, ask again
        until [[ -n "$get_public_ip" || -n "$public_ip" ]]; do
            echo "Invalid input."
            read -e -p "Public IPv4 address / hostname: " public_ip
        done
        [[ -z "$public_ip" ]] && public_ip="$get_public_ip"
    fi
    # If system has a single IPv6, it is selected automatically
    if [[ $(ip -6 addr | grep -c 'inet6 [23]') -eq 1 ]]; then
        ip6=$(ip -6 addr | grep 'inet6 [23]' | cut -d '/' -f 1 | grep -oE '([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}')
    fi
    # If system has multiple IPv6, ask the user to select one
    if [[ $(ip -6 addr | grep -c 'inet6 [23]') -gt 1 ]]; then
        number_of_ip6=$(ip -6 addr | grep -c 'inet6 [23]')
        echo
        echo "Which IPv6 address should be used?"
        ip -6 addr | grep 'inet6 [23]' | cut -d '/' -f 1 | grep -oE '([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}' | nl -s ') '
        read -e -p "IPv6 address [1]: " ip6_number
        until [[ -z "$ip6_number" || "$ip6_number" =~ ^[0-9]+$ && "$ip6_number" -le "$number_of_ip6" ]]; do
            echo "$ip6_number: invalid selection."
            read -e -p "IPv6 address [1]: " ip6_number
        done
        [[ -z "$ip6_number" ]] && ip6_number="1"
        ip6=$(ip -6 addr | grep 'inet6 [23]' | cut -d '/' -f 1 | grep -oE '([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}' | sed -n "$ip6_number"p)
    fi
    echo
    echo "Which protocol should OpenVPN use?"
    echo "   1) UDP (recommended)"
    echo "   2) TCP"
    read -e -p "Protocol [1]: " protocol
    until [[ -z "$protocol" || "$protocol" =~ ^[12]$ ]]; do
        echo "$protocol: invalid selection."
        read -e -p "Protocol [1]: " protocol
    done
    case "$protocol" in
        1|"")
        protocol=udp
        ;;
        2)
        protocol=tcp
        ;;
    esac
    echo
    echo "What port should OpenVPN listen to?"
    read -e -p "Port [1194]: " port
    until [[ -z "$port" || "$port" =~ ^[0-9]+$ && "$port" -le 65535 ]]; do
        echo "$port: invalid port."
        read -e -p "Port [1194]: " port
    done
    [[ -z "$port" ]] && port="1194"
    echo
    echo "Select a DNS server for the clients:"
    echo "   1) Current system resolvers"
    echo "   2) Google"
    echo "   3) 1.1.1.1"
    echo "   4) OpenDNS"
    echo "   5) Quad9"
    echo "   6) AdGuard"
    read -e -p "DNS server [1]: " dns
    until [[ -z "$dns" || "$dns" =~ ^[1-6]$ ]]; do
        echo "$dns: invalid selection."
        read -e -p "DNS server [1]: " dns
    done
    # select auth_user_pass
    echo
    echo "Select a validation type for user authentication:"
    echo "   1) 证书"
    echo "   2) 证书+账号"
    read -e -p "validation type [1]: " enable_auth_user_pass
    until [[ -z "$enable_auth_user_pass" || "$enable_auth_user_pass" =~ ^[1-2]$ ]]; do
        echo "$enable_auth_user_pass: invalid selection."
        read -e -p "validation type [1]: " enable_auth_user_pass
    done
    # create folder
    mkdir -p /etc/openvpn/server
    echo
    echo "OpenVPN installation is ready to begin."
    # Install a firewall in the rare case where one is not already available
    if ! systemctl is-active --quiet firewalld.service && ! hash iptables 2>/dev/null; then
        if [[ "$os" == "centos" || "$os" == "fedora" ]]; then
            firewall="firewalld"
            # We don't want to silently enable firewalld, so we give a subtle warning
            # If the user continues, firewalld will be installed and enabled during setup
            echo "firewalld, which is required to manage routing tables, will also be installed."
        elif [[ "$os" == "debian" || "$os" == "ubuntu" ]]; then
            # iptables is way less invasive than firewalld so no warning is given
            firewall="iptables"
        fi
    fi
    read -n1 -r -p "Press any key to continue..."
    # If running inside a container, disable LimitNPROC to prevent conflicts
    if systemd-detect-virt -cq; then
        mkdir /etc/systemd/system/openvpn-server@server.service.d/ 2>/dev/null
        echo "[Service]
LimitNPROC=infinity" > /etc/systemd/system/openvpn-server@server.service.d/disable-limitnproc.conf
    fi
    if [[ "$os" = "debian" || "$os" = "ubuntu" ]]; then
        apt-get update
        apt-get install -y openvpn openssl ca-certificates ${firewall}
    elif [[ "$os" = "centos" ]]; then
        yum install -y epel-release
        yum install -y openvpn openssl ca-certificates tar ${firewall}
    else
        # Else, OS must be Fedora
        dnf install -y openvpn openssl ca-certificates tar ${firewall}
    fi
    # If firewalld was just installed, enable it
    if [[ "$firewall" == "firewalld" ]]; then
        systemctl enable --now firewalld.service
    fi
    # Get easy-rsa
    easy_rsa_url='https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.7/EasyRSA-3.0.7.tgz'
    mkdir -p /etc/openvpn/server/easy-rsa/
    { wget -qO- "$easy_rsa_url" 2>/dev/null || curl -sL "$easy_rsa_url" ; } | tar xz -C /etc/openvpn/server/easy-rsa/ --strip-components 1
    chown -R root:root /etc/openvpn/server/easy-rsa/
    cd /etc/openvpn/server/easy-rsa/
    # Create the PKI, set up the CA and the server and client certificates
    ./easyrsa init-pki
    ./easyrsa --batch build-ca nopass
    EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-server-full server nopass
#        EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-client-full "$client" nopass
    EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl
    # Move the stuff we need
    cp pki/ca.crt pki/private/ca.key pki/issued/server.crt pki/private/server.key pki/crl.pem /etc/openvpn/server
    # CRL is read with each client connection, while OpenVPN is dropped to nobody
    chown nobody:"$group_name" /etc/openvpn/server/crl.pem
    # Without +x in the directory, OpenVPN can't run a stat() on the CRL file
    chmod o+x /etc/openvpn/server/
    # Generate key for tls-crypt
    openvpn --genkey --secret /etc/openvpn/server/tc.key
    # Create the DH parameters file using the predefined ffdhe2048 group
    echo '-----BEGIN DH PARAMETERS-----
MIIBCAKCAQEA//////////+t+FRYortKmq/cViAnPTzx2LnFg84tNpWp4TZBFGQz
+8yTnc4kmz75fS/jY2MMddj2gbICrsRhetPfHtXV/WVhJDP1H18GbtCFY2VVPe0a
87VXE15/V8k1mE8McODmi3fipona8+/och3xWKE2rec1MKzKT0g6eXq8CrGCsyT7
YdEIqUuyyOP7uWrat2DX9GgdT0Kj3jlN9K5W7edjcrsZCwenyO4KbXCeAvzhzffi
7MA0BM0oNC9hkXL+nOmFg/+OTxIy7vKBg8P+OxtMb61zO7X8vC7CIAXFjvGDfRaD
ssbzSibBsu/6iGtCOGEoXJf//////////wIBAg==
-----END DH PARAMETERS-----' > /etc/openvpn/server/dh.pem
    # Generate server.conf
    echo "local $ip
port $port
proto $protocol
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
auth SHA512
tls-crypt tc.key
topology subnet
server 10.8.0.0 255.255.255.0" > /etc/openvpn/server/server.conf
    # IPv6
    if [[ -z "$ip6" ]]; then
        echo 'push "redirect-gateway def1 bypass-dhcp"' >> /etc/openvpn/server/server.conf
    else
        echo 'server-ipv6 fddd:1194:1194:1194::/64' >> /etc/openvpn/server/server.conf
        echo 'push "redirect-gateway def1 ipv6 bypass-dhcp"' >> /etc/openvpn/server/server.conf
    fi
    echo 'ifconfig-pool-persist ipp.txt' >> /etc/openvpn/server/server.conf
    # DNS
    case "$dns" in
        1|"")
            # Locate the proper resolv.conf
            # Needed for systems running systemd-resolved
            if grep -q '^nameserver 127.0.0.53' "/etc/resolv.conf"; then
                resolv_conf="/run/systemd/resolve/resolv.conf"
            else
                resolv_conf="/etc/resolv.conf"
            fi
            # Obtain the resolvers from resolv.conf and use them for OpenVPN
            grep -v '^#\|^;' "$resolv_conf" | grep '^nameserver' | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | while read line; do
                echo "push \"dhcp-option DNS $line\"" >> /etc/openvpn/server/server.conf
            done
        ;;
        2)
            echo 'push "dhcp-option DNS 8.8.8.8"' >> /etc/openvpn/server/server.conf
            echo 'push "dhcp-option DNS 8.8.4.4"' >> /etc/openvpn/server/server.conf
        ;;
        3)
            echo 'push "dhcp-option DNS 1.1.1.1"' >> /etc/openvpn/server/server.conf
            echo 'push "dhcp-option DNS 1.0.0.1"' >> /etc/openvpn/server/server.conf
        ;;
        4)
            echo 'push "dhcp-option DNS 208.67.222.222"' >> /etc/openvpn/server/server.conf
            echo 'push "dhcp-option DNS 208.67.220.220"' >> /etc/openvpn/server/server.conf
        ;;
        5)
            echo 'push "dhcp-option DNS 9.9.9.9"' >> /etc/openvpn/server/server.conf
            echo 'push "dhcp-option DNS 149.112.112.112"' >> /etc/openvpn/server/server.conf
        ;;
        6)
            echo 'push "dhcp-option DNS 176.103.130.130"' >> /etc/openvpn/server/server.conf
            echo 'push "dhcp-option DNS 176.103.130.131"' >> /etc/openvpn/server/server.conf
        ;;
    esac
    echo "keepalive 10 120
cipher AES-256-CBC
user nobody
group $group_name
persist-key
persist-tun
# duplicate-cn     # 允许多个客户端共用一个证书
status openvpn-status.log
log openvpn.log
verb 3
mute 20
crl-verify crl.pem" >> /etc/openvpn/server/server.conf
    if [[ "$protocol" = "udp" ]]; then
        echo "explicit-exit-notify" >> /etc/openvpn/server/server.conf
    fi
    # auth-user-pass
    case "${enable_auth_user_pass}" in
        1|"")
        ;;
        2)
        touch /etc/openvpn/server/openvpn-password.log || exit 1
        touch /etc/openvpn/psw-file || exit 1
        chmod o+w /etc/openvpn/server/openvpn-password.log
        cat > /etc/openvpn/checkpsw.sh<<-EOF
#!/bin/sh
###########################################################
# checkpsw.sh (C) 2004 Mathias Sundman <mathias@openvpn.se>
#
# This script will authenticate OpenVPN users against
# a plain text file. The passfile should simply contain
# one row per user with the username first followed by
# one or more space(s) or tab(s) and then the password.

PASSFILE="/etc/openvpn/psw-file"
LOG_FILE="/etc/openvpn/server/openvpn-password.log"
TIME_STAMP=\`date "+%Y-%m-%d %T"\`

###########################################################

if [ ! -r "\${PASSFILE}" ]; then
  echo "\${TIME_STAMP}: Could not open password file \"\${PASSFILE}\" for reading." >> \${LOG_FILE}
  exit 1
fi

CORRECT_PASSWORD=\`awk '!/^;/&&!/^#/&&\$1=="'\${username}'"{print \$2;exit}' \${PASSFILE}\`

COMMON_NAME=\`awk '!/^;/&&!/^#/&&\$1=="'\${username}'"{print \$3;exit}' \${PASSFILE}\`

if [ "\${CORRECT_PASSWORD}" = "" ]; then
  echo "\${TIME_STAMP}: User does not exist: client=\"\${common_name}\", username=\"\${username}\", password=\"\${password}\"." >> \${LOG_FILE}
  exit 1
fi

if [ "\${password}" = "\${CORRECT_PASSWORD}" ] && [ "\${common_name}.ovpn" = "\${COMMON_NAME}" ]; then
  echo "\${TIME_STAMP}: Successful authentication: client=\"\${common_name}\", username=\"\${username}\"." >> \${LOG_FILE}
  exit 0
fi

echo "\${TIME_STAMP}: Incorrect password: client=\"\${common_name}\", username=\"\${username}\", password=\"\${password}\"." >> \${LOG_FILE}
exit 1
EOF
        chmod o+x /etc/openvpn/checkpsw.sh
        echo 'auth-user-pass-verify /etc/openvpn/checkpsw.sh via-env' >> /etc/openvpn/server/server.conf
        echo 'script-security 3' >> /etc/openvpn/server/server.conf
        ;;
    esac
    # Enable net.ipv4.ip_forward for the system
    echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/30-openvpn-forward.conf
    # Enable without waiting for a reboot or service restart
    echo 1 > /proc/sys/net/ipv4/ip_forward
    if [[ -n "$ip6" ]]; then
        # Enable net.ipv6.conf.all.forwarding for the system
        echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.d/30-openvpn-forward.conf
        # Enable without waiting for a reboot or service restart
        echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
    fi
    if systemctl is-active --quiet firewalld.service; then
        # Using both permanent and not permanent rules to avoid a firewalld
        # reload.
        # We don't use --add-service=openvpn because that would only work with
        # the default port and protocol.
        firewall-cmd --add-port="$port"/"$protocol"
        firewall-cmd --zone=trusted --add-source=10.8.0.0/24
        firewall-cmd --permanent --add-port="$port"/"$protocol"
        firewall-cmd --permanent --zone=trusted --add-source=10.8.0.0/24
        # Set NAT for the VPN subnet
        firewall-cmd --direct --add-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to "$ip"
        firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to "$ip"
        if [[ -n "$ip6" ]]; then
            firewall-cmd --zone=trusted --add-source=fddd:1194:1194:1194::/64
            firewall-cmd --permanent --zone=trusted --add-source=fddd:1194:1194:1194::/64
            firewall-cmd --direct --add-rule ipv6 nat POSTROUTING 0 -s fddd:1194:1194:1194::/64 ! -d fddd:1194:1194:1194::/64 -j SNAT --to "$ip6"
            firewall-cmd --permanent --direct --add-rule ipv6 nat POSTROUTING 0 -s fddd:1194:1194:1194::/64 ! -d fddd:1194:1194:1194::/64 -j SNAT --to "$ip6"
        fi
    else
        # Create a service to set up persistent iptables rules
        iptables_path=$(command -v iptables)
        ip6tables_path=$(command -v ip6tables)
        # nf_tables is not available as standard in OVZ kernels. So use iptables-legacy
        # if we are in OVZ, with a nf_tables backend and iptables-legacy is available.
        if [[ $(systemd-detect-virt) == "openvz" ]] && readlink -f "$(command -v iptables)" | grep -q "nft" && hash iptables-legacy 2>/dev/null; then
            iptables_path=$(command -v iptables-legacy)
            ip6tables_path=$(command -v ip6tables-legacy)
        fi
        echo "[Unit]
Before=network.target
[Service]
Type=oneshot
ExecStart=$iptables_path -t nat -A POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $ip
ExecStart=$iptables_path -I INPUT -p $protocol --dport $port -j ACCEPT
ExecStart=$iptables_path -I FORWARD -s 10.8.0.0/24 -j ACCEPT
ExecStart=$iptables_path -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStop=$iptables_path -t nat -D POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $ip
ExecStop=$iptables_path -D INPUT -p $protocol --dport $port -j ACCEPT
ExecStop=$iptables_path -D FORWARD -s 10.8.0.0/24 -j ACCEPT
ExecStop=$iptables_path -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT" > /etc/systemd/system/openvpn-iptables.service
        if [[ -n "$ip6" ]]; then
            echo "ExecStart=$ip6tables_path -t nat -A POSTROUTING -s fddd:1194:1194:1194::/64 ! -d fddd:1194:1194:1194::/64 -j SNAT --to $ip6
ExecStart=$ip6tables_path -I FORWARD -s fddd:1194:1194:1194::/64 -j ACCEPT
ExecStart=$ip6tables_path -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStop=$ip6tables_path -t nat -D POSTROUTING -s fddd:1194:1194:1194::/64 ! -d fddd:1194:1194:1194::/64 -j SNAT --to $ip6
ExecStop=$ip6tables_path -D FORWARD -s fddd:1194:1194:1194::/64 -j ACCEPT
ExecStop=$ip6tables_path -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT" >> /etc/systemd/system/openvpn-iptables.service
        fi
        echo "RemainAfterExit=yes
[Install]
WantedBy=multi-user.target" >> /etc/systemd/system/openvpn-iptables.service
        systemctl enable --now openvpn-iptables.service
    fi
    # If SELinux is enabled and a custom port was selected, we need this
    if sestatus 2>/dev/null | grep "Current mode" | grep -q "enforcing" && [[ "$port" != 1194 ]]; then
        # Install semanage if not already present
        if ! hash semanage 2>/dev/null; then
            if [[ "$os_version" -eq 7 ]]; then
                # Centos 7
                yum install -y policycoreutils-python
            else
                # CentOS 8 or Fedora
                dnf install -y policycoreutils-python-utils
            fi
        fi
        semanage port -a -t openvpn_port_t -p "$protocol" "$port"
    fi
    # If the server is behind NAT, use the correct IP address
    [[ -n "$public_ip" ]] && ip="$public_ip"
    # client-common.txt is created so we have a template to add further users later
    echo "client
dev tun
proto $protocol
remote $ip $port
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA512
cipher AES-256-CBC
ignore-unknown-option block-outside-dns
block-outside-dns
verb 3" > /etc/openvpn/server/client-common.txt
    # auth-user-pass client config
    case "${enable_auth_user_pass}" in
        1|"")
        ;;
        2)
        echo "auth-user-pass" >> /etc/openvpn/server/client-common.txt
        ;;
    esac
    # Enable and start the OpenVPN service
    systemctl enable --now openvpn-server@server.service
    echo
    echo -e "${Green_font_prefix}Finished!${Font_color_suffix}"
    echo
    # echo "The client configuration is available in:" ~/"$client.ovpn"
    echo -e "${Info}${Green_font_prefix}New clients can be added by running this script again.${Font_color_suffix}\n"
    menu_status
}

Remove_OpenVPN(){
    check_OpenVPN
    [[ $? -eq 1 ]] && return 1
    read -e -p "Confirm OpenVPN removal? [y/N]: " remove
    until [[ "$remove" =~ ^[yYnN]*$ ]]; do
        echo "$remove: invalid selection."
        read -e -p "Confirm OpenVPN removal? [y/N]: " remove
    done
    if [[ "$remove" =~ ^[yY]$ ]]; then
        port=$(grep '^port ' /etc/openvpn/server/server.conf | cut -d " " -f 2)
        protocol=$(grep '^proto ' /etc/openvpn/server/server.conf | cut -d " " -f 2)
        if systemctl is-active --quiet firewalld.service; then
            ip=$(firewall-cmd --direct --get-rules ipv4 nat POSTROUTING | grep '\-s 10.8.0.0/24 '"'"'!'"'"' -d 10.8.0.0/24' | grep -oE '[^ ]+$')
            # Using both permanent and not permanent rules to avoid a firewalld reload.
            firewall-cmd --remove-port="$port"/"$protocol"
            firewall-cmd --zone=trusted --remove-source=10.8.0.0/24
            firewall-cmd --permanent --remove-port="$port"/"$protocol"
            firewall-cmd --permanent --zone=trusted --remove-source=10.8.0.0/24
            firewall-cmd --direct --remove-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to "$ip"
            firewall-cmd --permanent --direct --remove-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to "$ip"
            if grep -qs "server-ipv6" /etc/openvpn/server/server.conf; then
                ip6=$(firewall-cmd --direct --get-rules ipv6 nat POSTROUTING | grep '\-s fddd:1194:1194:1194::/64 '"'"'!'"'"' -d fddd:1194:1194:1194::/64' | grep -oE '[^ ]+$')
                firewall-cmd --zone=trusted --remove-source=fddd:1194:1194:1194::/64
                firewall-cmd --permanent --zone=trusted --remove-source=fddd:1194:1194:1194::/64
                firewall-cmd --direct --remove-rule ipv6 nat POSTROUTING 0 -s fddd:1194:1194:1194::/64 ! -d fddd:1194:1194:1194::/64 -j SNAT --to "$ip6"
                firewall-cmd --permanent --direct --remove-rule ipv6 nat POSTROUTING 0 -s fddd:1194:1194:1194::/64 ! -d fddd:1194:1194:1194::/64 -j SNAT --to "$ip6"
            fi
        else
            systemctl disable --now openvpn-iptables.service
            rm -f /etc/systemd/system/openvpn-iptables.service
        fi
        if sestatus 2>/dev/null | grep "Current mode" | grep -q "enforcing" && [[ "$port" != 1194 ]]; then
            semanage port -d -t openvpn_port_t -p "$protocol" "$port"
        fi
        systemctl disable --now openvpn-server@server.service
        rm -rf /etc/openvpn
        rm -f /etc/systemd/system/openvpn-server@server.service.d/disable-limitnproc.conf
        rm -f /etc/sysctl.d/30-openvpn-forward.conf
        if [[ "$os" = "debian" || "$os" = "ubuntu" ]]; then
            apt-get remove --purge -y openvpn
        else
            # Else, OS must be CentOS or Fedora
            yum remove -y openvpn
        fi
        echo
        echo -e "${Info}${Green_font_prefix}OpenVPN removed!${Font_color_suffix}\n"
    else
        echo
        echo -e "${Info}${Green_font_prefix}OpenVPN removal aborted!${Font_color_suffix}\n"
    fi
}

Add_client(){
    check_OpenVPN
    [[ $? -eq 1 ]] && return 1
    [[ ! -e /etc/openvpn/client ]] && mkdir -p /etc/openvpn/client
    echo
    read -e -p "Provide a name for the client: " unsanitized_client
    client=$(sed 's/[^0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-]/_/g' <<< "$unsanitized_client")
    while [[ -z "$client" || -e /etc/openvpn/server/easy-rsa/pki/issued/"$client".crt ]]; do
        echo "$client: invalid name."
        read -e -p "Provide a name for the client: " unsanitized_client
        client=$(sed 's/[^0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-]/_/g' <<< "$unsanitized_client")
    done
    # set username and password
	if [[ ! -z "`grep "^auth-user-pass-verify" /etc/openvpn/server/server.conf `" ]]; then
		# username can't be duplicate
		echo
		read -e -p "Enter a username for the client (${client}.ovpn): " client_username
		check_username
		until [[ "${username_flag}" -eq 1 ]]; do
			read -e -p "Enter a username for the client (${client}.ovpn): " client_username
			check_username
		done
		# password
		echo
		read -e -p "Enter a password for the client (${client}.ovpn): " client_password
		until [[ ! -z "$client_password" ]]; do
			echo "$client_password: password is null."
			read -e -p "Enter a password for the client (${client}.ovpn): " client_password
		done
		echo "${client_username} ${client_password} ${client}.ovpn" >> /etc/openvpn/psw-file
	fi
    cd /etc/openvpn/server/easy-rsa/
    EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-client-full "$client" nopass
    # Generates the custom client.ovpn
    new_client
    echo
    echo -e "${Info}${Green_font_prefix}client[${client}.ovpn] added. Configuration available in: /etc/openvpn/client/${client}.ovpn${Font_color_suffix}\n"
}

View_client(){
    check_OpenVPN
    [[ $? -eq 1 ]] && return 1
    # This option could be documented a bit better and maybe even be simplified
    # ...but what can I say, I want some sleep too
    number_of_clients=$(tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep -c "^V")
    if [[ "$number_of_clients" = 0 ]]; then
        echo -e "\n${Tip}${Red_font_prefix}There are no existing clients!\n${Font_color_suffix}" && return 0
    fi
    echo
    echo -e " ${Info}${Green_font_prefix}All clients:${Font_color_suffix}"
    tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | nl -s ') ' && echo
}

Revoke_client(){
    check_OpenVPN
    [[ $? -eq 1 ]] && return 1
    # This option could be documented a bit better and maybe even be simplified
    # ...but what can I say, I want some sleep too
    number_of_clients=$(tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep -c "^V")
    if [[ "$number_of_clients" = 0 ]]; then
        echo -e "${Green_font_prefix}\nThere are no existing clients!\n${Font_color_suffix}" && return 0
    fi
    echo
    echo "Select the client to revoke:"
    tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | nl -s ') '
    read -e -p "Client: " client_number
    until [[ "$client_number" =~ ^[0-9]+$ && "$client_number" -le "$number_of_clients" ]]; do
        echo "$client_number: invalid selection."
        read -e -p "Client: " client_number
    done
    client=$(tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | sed -n "$client_number"p)
    echo
    read -e -p "Confirm $client revocation? [y/N]: " revoke
    until [[ "$revoke" =~ ^[yYnN]*$ ]]; do
        echo "$revoke: invalid selection."
        read -e -p "Confirm $client revocation? [y/N]: " revoke
    done
    if [[ "$revoke" =~ ^[yY]$ ]]; then
        # remove username and password
        psw_line=$(grep "${client}.ovpn" /etc/openvpn/psw-file)
        sed -i "s/${psw_line}/# ${psw_line}/" /etc/openvpn/psw-file
        # remove client cert
        cd /etc/openvpn/server/easy-rsa/
        ./easyrsa --batch revoke "$client"
        EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl
        rm -f /etc/openvpn/server/crl.pem
        rm -f /etc/openvpn/client/"${client}.ovpn"
        cp /etc/openvpn/server/easy-rsa/pki/crl.pem /etc/openvpn/server/crl.pem
        # CRL is read with each client connection, when OpenVPN is dropped to nobody
        chown nobody:"$group_name" /etc/openvpn/server/crl.pem
        echo -e "\n${Info}${Green_font_prefix}${client}.ovpn revoked!${Font_color_suffix}\n"
    else
        echo -e "\n${Info}${Red_font_prefix}${client}.ovpn revocation aborted!${Font_color_suffix}\n"
    fi
}

View_config(){
    check_OpenVPN
    [[ $? -eq 1 ]] && return 1
    cat -n ${server_config_file} && echo
}

View_OpenVPN_log(){
    check_OpenVPN
    [[ $? -eq 1 ]] && return 1
	[[ ! -e ${openvpn_log_file} ]] && echo -e "${Error} OpenVPN日志文件不存在 !" && return 1
	echo && echo -e "${Tip} 按 ${Red_font_prefix}Ctrl+C${Font_color_suffix} 终止查看日志" && echo -e "如果需要查看完整日志内容，请用 ${Red_font_prefix}cat ${openvpn_log_file}${Font_color_suffix} 命令。" && echo
	tail -f ${openvpn_log_file}
}

View_Password_log(){
    check_OpenVPN
    [[ $? -eq 1 ]] && return 1
    [[ ! -e ${password_log_file} ]] && echo -e "${Error} 当前用户验证方式无账号登陆日志 !" && return 1
	echo && echo -e "${Tip} 按 ${Red_font_prefix}Ctrl+C${Font_color_suffix} 终止查看日志" && echo -e "如果需要查看完整日志内容，请用 ${Red_font_prefix}cat ${password_log_file}${Font_color_suffix} 命令。" && echo
	tail -f ${password_log_file}
}

View_Password_file(){
    check_OpenVPN
    [[ $? -eq 1 ]] && return 1
    [[ ! -e "/etc/openvpn/psw-file" ]] && echo -e "${Error} 当前用户验证方式无用户账号密码 !" && return 1
	echo && echo -e "${Tip} 按 ${Red_font_prefix}Ctrl+C${Font_color_suffix} 终止查看日志" && echo -e "如果需要查看完整日志内容，请用 ${Red_font_prefix}cat ${password_file}${Font_color_suffix} 命令。" && echo
	tail -f /etc/openvpn/psw-file
}

Start_OpenVPN(){
    check_OpenVPN
    [[ $? -eq 1 ]] && return 1
    service openvpn-server@server start
    echo -e "openVPN starting..."
    sleep 2s
    menu_status
}

Stop_OpenVPN(){
    check_OpenVPN
    [[ $? -eq 1 ]] && return 1
    service openvpn-server@server stop
    echo -e "openVPN stopping..."
    sleep 2s
    menu_status
}

Restart_OpenVPN(){
    check_OpenVPN
    [[ $? -eq 1 ]] && return 1
    service openvpn-server@server restart
    echo -e "openVPN restarting..."
    sleep 2s
    menu_status
}

check_pid(){
	PID=`ps -ef |grep -v grep | grep "/usr/sbin/openvpn" |awk '{print $2}'`
}

check_OpenVPN(){
    if [[ ! -e ${server_config_file} ]]; then
		echo -e " 当前状态: ${Red_font_prefix}未安装 openVPN${Font_color_suffix}\n" && return 1
	fi
	return 0
}

# ------------------------------------------------------------------

main(){
    echo -e "****************************
  【openVPN 一键管理脚本】

  ${Green_font_prefix}1.${Font_color_suffix} 安装 openVPN
  ${Green_font_prefix}2.${Font_color_suffix} 卸载 openVPN
--------------------
  ${Green_font_prefix}3.${Font_color_suffix} 查看 服务端配置
  ${Green_font_prefix}4.${Font_color_suffix} 修改 服务端配置
--------------------
  ${Green_font_prefix}5.${Font_color_suffix} 查看 客户端
  ${Green_font_prefix}6.${Font_color_suffix} 添加 客户端
  ${Green_font_prefix}7.${Font_color_suffix} 撤销 客户端
--------------------
  ${Green_font_prefix}8.${Font_color_suffix} 启动 openVPN
  ${Green_font_prefix}9.${Font_color_suffix} 停止 openVPN
 ${Green_font_prefix}10.${Font_color_suffix} 重启 openVPN
 ${Green_font_prefix}11.${Font_color_suffix} 查看 openVPN 运行日志
 ${Green_font_prefix}12.${Font_color_suffix} 查看 openVPN 登陆日志
 ${Green_font_prefix}13.${Font_color_suffix} 查看 openVPN 用户账号
--------------------
 ${Green_font_prefix}14.${Font_color_suffix} 退出脚本
"
}
menu_status
while true
do
    main
    read -e -p "请输入数字 [1-14]：" num
    case "$num" in
        1)
        Install_OpenVPN
        ;;
        2)
        Remove_OpenVPN
        ;;
        3)
        View_config
        ;;
        4)
        echo -e "\n${Tip}暂不支持\n"
        ;;
        5)
        View_client
        ;;
        6)
        Add_client
        ;;
        7)
        Revoke_client
        ;;
        8)
        Start_OpenVPN
        ;;
        9)
        Stop_OpenVPN
        ;;
        10)
        Restart_OpenVPN
        ;;
        11)
        View_OpenVPN_log
        ;;
        12)
        View_Password_log
        ;;
        13)
        View_Password_file
        ;;
        14)
        exit 0
        ;;
        *)
        echo -e "${Error} 请输入正确的数字 [1-14]"
        ;;
    esac
done