# Void

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
main_interface=$(ip route get 8.8.8.8 | awk -- '{printf $5}')

random() {
	tr </dev/urandom -dc A-Za-z0-9 | head -c5
	echo
}

gen64() {
	ip64() {
		echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
	}
	echo "$1:$(ip64):$(ip64):$(ip64):$(ip64):$(ip64):$(ip64)"
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
    if [[ $TYPE -eq 1 ]]
        then
          echo "$USERNAME/$PASSWORD/$IP4/$port/$(gen64 $IP6)"
        else
          echo "$USERNAME/$PASSWORD/$IP4/$FIRST_PORT/$(gen64 $IP6)"
        fi    
    done
}

gen_data_multiuser() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        if [[ $TYPE -eq 1 ]]
        then
          echo "$(random)/$(random)/$IP4/$port/$(gen64 $IP6)"
        else
          echo "$(random)/$(random)/$IP4/$FIRST_PORT/$(gen64 $IP6)"
        fi    
    done
}

install_3proxy() {
    echo "Installing 3proxy"
    mkdir -p /3proxy
    cd /3proxy
    #URL="https://github.com/z3APA3A/3proxy/archive/0.9.3.tar.gz"
    URL="https://raw.githubusercontent.com/mrtoan2808/3proxy-ipv6/master/3proxy-0.9.3.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-0.9.3
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    mv /3proxy/3proxy-0.9.3/bin/3proxy /usr/local/etc/3proxy/bin/
    wget https://raw.githubusercontent.com/mrtoan2808/3proxy-ipv6/master/3proxy.service-Centos8 --output-document=/3proxy/3proxy-0.9.3/scripts/3proxy.service2
    cp /3proxy/3proxy-0.9.3/scripts/3proxy.service2 /usr/lib/systemd/system/3proxy.service
    systemctl link /usr/lib/systemd/system/3proxy.service
    systemctl daemon-reload
    #systemctl enable 3proxy
    echo "* hard nofile 999999" >>  /etc/security/limits.conf
    echo "* soft nofile 999999" >>  /etc/security/limits.conf
    echo "net.ipv6.conf.$main_interface.proxy_ndp=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.proxy_ndp=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.default.forwarding=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    echo "net.ipv6.ip_nonlocal_bind = 1" >> /etc/sysctl.conf
    sysctl -p
    systemctl stop firewalld
    systemctl disable firewalld

    cd $WORKDIR
}

gen_3proxy() {
    cat <<EOF
daemon
maxconn 5000
nserver 1.1.1.1
nserver 8.8.4.4
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456 
flush
auth strong
users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})
$(awk -F "/" '{print "auth strong\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e" $5 "\n" \
"flush\n"}' ${WORKDATA})
EOF
}

gen_iptables() {
    cat <<EOF
    $(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA}) 
EOF
}

gen_ifconfig() {
    cat <<EOF
    $(awk -F "/" '{print "ifconfig '$main_interface' inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

upload_proxy() {
    cd $WORKDIR
    local PASS=$(random)
    zip --password $PASS proxy.zip proxy.txt
    URL=$(curl -F "file=@proxy.zip" https://file.io)

    echo "Proxy is ready! Format IP:PORT:LOGIN:PASS"
    echo "Download zip archive from: ${URL}"
    echo "Password: ${PASS}"
}

# Begin
echo "Welcome to Install Proxy IPV6 by One"
echo "Installing apps"
yum -y install gcc net-tools bsdtar zip make >/dev/null

install_3proxy

echo "Working folder = /home/proxy-installer"
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir $WORKDIR && cd $_

USERNAME=$(random)
PASSWORD=$(random)
IP4=$(curl -4 -s icanhazip.com)
#IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')
echo "Input IPV6 [abcd:1234]"
read IP6

echo "Internal ip = ${IP4}. Exteranl sub for ip6 = ${IP6}"

echo "How many proxy do you want to create? Example 500"
read COUNT
echo "You selected create " $COUNT " proxy"

FIRST_PORT=10000
LAST_PORT=$(($FIRST_PORT + $COUNT))

echo "What type of proxy do you want to create?"
echo "1 - Static"
echo "2 or (Any number) - Rotate"
read TYPE
if [[ $TYPE -eq 1 ]]
then
  echo "You selected Proxy Static"
else
  echo "You selected Proxy Rotate"
fi

echo "Do you want create One User or Multi User?"
echo "1 - One"
echo "2 or (Any number) - Multi"
read NUSER
if [[ NUSER -eq 1 ]]
then
  echo "You selected One User"
  gen_data >$WORKDIR/data.txt
else
  echo "You selected Multi User"
  gen_data_multiuser >$WORKDIR/data.txt
fi

gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
echo NM_CONTROLLED="no" >> /etc/sysconfig/network-scripts/ifcfg-${main_interface}
chmod +x $WORKDIR/boot_*.sh /etc/rc.local

gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

cat >>/etc/rc.local <<EOF
systemctl start NetworkManager.service
#ifup ${main_interface}
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 65535
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &
EOF

bash /etc/rc.local

gen_proxy_file_for_user

echo "------ Done ------"

upload_proxy

echo "Proxy local file from: ${WORKDIR}/proxy.txt"
# End
