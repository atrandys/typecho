#!/bin/bash
 
function blue(){
    echo -e "\033[34m\033[01m$1\033[0m"
}
function green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}
function red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}
function yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}
function bred(){
    echo -e "\033[31m\033[01m\033[05m$1\033[0m"
}
function byellow(){
    echo -e "\033[33m\033[01m\033[05m$1\033[0m"
}

#判断系统
check_os(){
if [ ! -e '/etc/redhat-release' ]; then
red "==============="
red " 仅支持CentOS7"
red "==============="
exit
fi
if  [ -n "$(grep ' 6\.' /etc/redhat-release)" ] ;then
red "==============="
red " 仅支持CentOS7"
red "==============="
exit
fi
if  [ -n "$(grep ' 8\.' /etc/redhat-release)" ] ;then
red "==============="
red " 仅支持CentOS7"
red "==============="
exit
fi
}

disable_selinux(){
    firestatus=`systemctl status firewalld | grep "Active: active"`
    if [[ ! -z $firestatus ]]; then
        green "检测到firewall开启状态，添加放行80/443端口规则"
        firewall-cmd --zone=public --add-port=80/tcp --permanent
	firewall-cmd --zone=public --add-port=443/tcp --permanent
    fi
    CHECK=$(grep SELINUX= /etc/selinux/config | grep -v "#")
    if [ "$CHECK" != "SELINUX=disabled" ]; then
        green "检测到SELinux开启状态，添加放行80/443端口规则"
        semanage port -a -t http_port_t -p tcp 80
        semanage port -a -t http_port_t -p tcp 443
    fi
}

check_domain(){
    green "======================="
    yellow "请输入绑定到本VPS的域名"
    green "======================="
    read your_domain
    real_addr=`ping ${your_domain} -c 1 | sed '1{s/[^(]*(//;s/).*//;q}'`
    local_addr=`curl ipv4.icanhazip.com`
    if [ $real_addr == $local_addr ] ; then
    	green "============================="
	green "域名解析正常，开始安装typecho"
	green "============================="
	sleep 1s
	download_wp
	install_php7
    	install_mysql
    	install_nginx
	config_php
    	install_wp
    else
        red "================================"
	red "域名解析地址与本VPS IP地址不一致"
	red "若你确认解析成功你可强制脚本继续运行"
	red "================================"
	read -p "是否强制运行 ?请输入 [Y/n] :" yn
	[ -z "${yn}" ] && yn="y"
	if [[ $yn == [Yy] ]]; then
            green "强制继续运行脚本"
	else
	    exit 1
	fi
    fi
}

install_php7(){

    green "==============="
    green " 1.安装必要软件"
    green "==============="
    sleep 1
    yum -y install epel-release
    sed -i "0,/enabled=0/s//enabled=1/" /etc/yum.repos.d/epel.repo
    yum -y install  unzip vim tcl expect curl socat
    echo
    echo
    green "=========="
    green "2.安装PHP7"
    green "=========="
    sleep 1
    rpm -Uvh https://mirror.webtatic.com/yum/el7/webtatic-release.rpm
    yum -y install php70w php70w-mysql php70w-gd php70w-xml php70w-fpm
    service php-fpm start
    chkconfig php-fpm on
    if [ `yum list installed | grep php70 | wc -l` -ne 0 ]; then
        echo
    	green "【checked】 PHP7安装成功"
	echo
	echo
	sleep 2
	php_status=1
    fi
}

install_mysql(){

    green "==============="
    green "  3.安装MySQL"
    green "==============="
    sleep 1
    wget http://repo.mysql.com/mysql-community-release-el7-5.noarch.rpm
    rpm -ivh mysql-community-release-el7-5.noarch.rpm
    yum -y install mysql-server
    systemctl enable mysqld.service
    systemctl start  mysqld.service
    if [ `yum list installed | grep mysql-community | wc -l` -ne 0 ]; then
    	green "【checked】 MySQL安装成功"
	echo
	echo
	sleep 2
	mysql_status=1
    fi
    echo
    echo
    green "==============="
    green "  4.配置MySQL"
    green "==============="
    sleep 2
    mysqlpasswd=$(cat /dev/urandom | head -1 | md5sum | head -c 8)
    
/usr/bin/expect << EOF
spawn mysql_secure_installation
expect "password for root" {send "\r"}
expect "root password" {send "Y\r"}
expect "New password" {send "$mysqlpasswd\r"}
expect "Re-enter new password" {send "$mysqlpasswd\r"}
expect "Remove anonymous users" {send "Y\r"}
expect "Disallow root login remotely" {send "Y\r"}
expect "database and access" {send "Y\r"}
expect "Reload privilege tables" {send "Y\r"}
spawn mysql -u root -p
expect "Enter password" {send "$mysqlpasswd\r"}
expect "mysql" {send "create database wordpress_db;\r"}
expect "mysql" {send "exit\r"}
EOF


}

install_nginx(){
    echo
    echo
    green "==============="
    green "  5.安装nginx"
    green "==============="
    sleep 1
    rpm -Uvh http://nginx.org/packages/centos/7/noarch/RPMS/nginx-release-centos-7-0.el7.ngx.noarch.rpm
    yum install -y nginx
    systemctl enable nginx.service
    systemctl stop nginx.service
    rm -f /etc/nginx/conf.d/default.conf
    rm -f /etc/nginx/nginx.conf
    mkdir /etc/nginx/ssl
    if [ `yum list installed | grep nginx | wc -l` -ne 0 ]; then
    	echo
	green "【checked】 nginx安装成功"
	echo
	echo
	sleep 1
	mysql_status=1
    fi

cat > /etc/nginx/nginx.conf <<-EOF
user  nginx;
worker_processes  1;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;
    sendfile        on;
    #tcp_nopush     on;
    keepalive_timeout  120;
    client_max_body_size 20m;
    #gzip  on;
    include /etc/nginx/conf.d/*.conf;
}
EOF

    curl https://get.acme.sh | sh
    ~/.acme.sh/acme.sh  --issue  -d $your_domain  --standalone
    ~/.acme.sh/acme.sh  --installcert  -d  $your_domain   \
        --key-file   /etc/nginx/ssl/$your_domain.key \
        --fullchain-file /etc/nginx/ssl/fullchain.cer
	
cat > /etc/nginx/conf.d/default.conf<<-EOF
server {
    listen 80 default_server;
    server_name _;
    return 404;  
}
server {
    listen 443 ssl default_server;
    server_name _;
    ssl_certificate /etc/nginx/ssl/fullchain.cer; 
    ssl_certificate_key /etc/nginx/ssl/$your_domain.key;
    return 404;
}
server { 
    listen       80;
    server_name  $your_domain;
    rewrite ^(.*)$  https://\$host\$1 permanent; 
}
server {
    listen 443 ssl http2;
    server_name $your_domain;
    root /usr/share/nginx/html;
    index index.php index.html;
    ssl_certificate /etc/nginx/ssl/fullchain.cer; 
    ssl_certificate_key /etc/nginx/ssl/$your_domain.key;
    ssl_stapling on;
    ssl_stapling_verify on;
    add_header Strict-Transport-Security "max-age=31536000";
    access_log /var/log/nginx/hostscube.log combined;
    location ~ \.php$ {
    	fastcgi_pass 127.0.0.1:9000;
    	fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    	include fastcgi_params;
    }
    location / {
       try_files \$uri \$uri/ /index.php?\$args;
    }
}
EOF

}

config_php(){

    echo
    green "===================="
    green " 6.配置php和php-fpm"
    green "===================="
    echo
    echo
    sleep 1
    sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 20M/;" /etc/php.ini
    sed -i "s/pm.start_servers = 5/pm.start_servers = 3/;s/pm.min_spare_servers = 5/pm.min_spare_servers = 3/;s/pm.max_spare_servers = 35/pm.max_spare_servers = 8/;" /etc/php-fpm.d/www.conf
    systemctl restart php-fpm.service
    systemctl restart nginx.service

}


download_wp(){

    yum -y install  wget
    mkdir /usr/share/wordpresstemp
    cd /usr/share/wordpresstemp/
    wget https://cn.wordpress.org/latest-zh_CN.zip
    if [ ! -f "/usr/share/wordpresstemp/latest-zh_CN.zip" ]; then
        red "从cn官网下载wordpress失败，尝试从github下载……"
	      wget https://github.com/atrandys/wordpress/raw/master/latest-zh_CN.zip    
    fi
    if [ ! -f "/usr/share/wordpresstemp/latest-zh_CN.zip" ]; then
	      red "我它喵的从github下载wordpress也失败了，请尝试手动安装……"
	      green "从wordpress官网下载包然后命名为latest-zh_CN.zip，新建目录/usr/share/wordpresstemp/，上传到此目录下即可"
	      exit 1
    fi
}

install_wp(){

    green "===================="
    green "  7.安装wordpress"
    green "===================="
    echo
    echo
    sleep 1
    cd /usr/share/nginx/html
    mv /usr/share/wordpresstemp/latest-zh_CN.zip ./
    unzip latest-zh_CN.zip
    mv wordpress/* ./
    cp wp-config-sample.php wp-config.php
    green "===================="
    green "  8.配置wordpress"
    green "===================="
    echo
    echo
    sleep 1
    sed -i "s/database_name_here/wordpress_db/;s/username_here/root/;s/password_here/$mysqlpasswd/;" /usr/share/nginx/html/wp-config.php
    echo "define('FS_METHOD', "direct");" >> /usr/share/nginx/html/wp-config.php
    chown -R nginx:root /usr/share/nginx/html/
    chmod -R 777 /usr/share/nginx/html/wp-content
    green "==========================================================="
    green " WordPress服务端配置已完成，请打开浏览器访问您的域名进行前台配置"
    green " 数据库密码等信息参考文件：/usr/share/nginx/html/wp-config.php"
    green "==========================================================="
}

uninstall_wp(){
    red "============================================="
    red "你的wordpress数据将全部丢失！！你确定要卸载吗？"
    read -s -n1 -p "按回车键开始卸载，按ctrl+c取消"
    yum remove -y php70w php70w-mysql php70w-gd php70w-xml php70w-fpm mysql nginx
    rm -rf /usr/share/nginx/html/*
    rm -rf /var/lib/mysql
    rm -rf /usr/share/mysql
    green "=========="
    green " 卸载完成"
    green "=========="
}

start_menu(){
    clear
    green "======================================="
    green " 介绍：适用于CentOS7，一键安装wordpress"
    green " 作者：atrandys"
    green " 网站：www.atrandys.com"
    green " Youtube：Randy's 堡垒"
    green "======================================="
    green "1. 一键安装wordpress"
    red "2. 卸载wordpress"
    yellow "0. 退出脚本"
    echo
    read -p "请输入数字:" num
    case "$num" in
    	1)
	check_os
	disable_selinux
        check_domain
	;;
	2)
	uninstall_wp
	;;
	0)
	exit 1
	;;
	*)
	clear
	echo "请输入正确数字"
	sleep 2s
	start_menu
	;;
    esac
}

start_menu
