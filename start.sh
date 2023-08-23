#!/bin/bash
sleep 1
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"
WHITLE="\033[37m"
MAGENTA="\033[35m"
CYAN="\033[36m"
BLUE="\033[34m"
BOLD="\033[01m"

error() {
    echo -e "$RED$BOLD$1$PLAIN"
}

success() {
    echo -e "$GREEN$BOLD$1$PLAIN"
}

warning() {
    echo -e "$YELLOW$BOLD$1$PLAIN"
}

info() {
    echo -e "$PLAIN$BOLD$1$PLAIN"
}

REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove")

[[ $EUID -ne 0 ]] && error "请切换至ROOT用户" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i"
    if [[ -n $SYS ]]; then
        break
    fi
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    if [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]]; then
        SYSTEM="${RELEASE[int]}"
        if [[ -n $SYSTEM ]]; then
            break
        fi
    fi
done

[[ -z $SYSTEM ]] && error "操作系统类型不支持" && exit 1

back2menu() {
    echo ""
    success "运行成功"
    read -rp "请输入“y”退出, 或按任意键回到主菜单：" back2menuInput
    case "$back2menuInput" in
        y) exit 1 ;;
        *) menu ;;
    esac
}

brefore_install() {
    if [[ ! $SYSTEM == "CentOS" ]]; then
        info "更新系统软件源"
        ${PACKAGE_UPDATE[int]}
    fi
    info "安装所需软件"
    ${PACKAGE_INSTALL[int]} curl wget sudo certbot
    if [[ $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_INSTALL[int]} cronie
        systemctl start crond
        systemctl enable crond
    else
        ${PACKAGE_INSTALL[int]} cron
        systemctl start cron
        systemctl enable cron
    fi
}

check_80(){
    # Fork from https://github.com/Misaka-blog/acme-script/blob/main/acme.sh
    if [[ -z $(type -P lsof) ]]; then
        if [[ ! $SYSTEM == "CentOS" ]]; then
            ${PACKAGE_UPDATE[int]}
        fi
        ${PACKAGE_INSTALL[int]} lsof
    fi
    
    warning "正在检测80端口是否占用..."
    sleep 1
    
    if [[  $(lsof -i:"80" | grep -i -c "listen") -eq 0 ]]; then
        success "检测到目前80端口未被占用"
        sleep 1
    else
        error "检测到目前80端口被其他程序被占用，以下为占用程序信息"
        lsof -i:"80"
        read -rp "如需结束占用进程请按Y，按其他键则退出 [Y/N]: " yn
        if [[ $yn =~ "Y"|"y" ]]; then
            lsof -i:"80" | awk '{print $2}' | grep -v "PID" | xargs kill -9
            sleep 1
        else
            exit 1
        fi
    fi
}

cert_update() {
    cron_tab=$(crontab -l)
    if [[ "${cron_tab}" == *"no crontab"* ]]; then 
        error "请先执行一次crontab -e"
        exit 1
    fi
    cat > "/etc/letsencrypt/renewal-hooks/post/$1.renew.sh" << EOF
    #!/bin/bash
    cat /etc/letsencrypt/live/$1*/fullchain.pem > /root/$1.fullchain.pem
    cat /etc/letsencrypt/live/$1*/privkey.pem > /root/$1.private_key.pem
EOF
    warning "测试证书自动续费..."
    chmod +x "/etc/letsencrypt/renewal-hooks/post/$1.renew.sh"
    bash "/etc/letsencrypt/renewal-hooks/post/$1.renew.sh"
    if crontab -l | grep -q "$1"; then
        warning "已存在$1的证书自动续期任务"
    else
        crontab -l > conf_temp && echo "0 0 * */2 * certbot renew --cert-name $1 --dry-run" >> conf_temp && crontab conf_temp && rm -f conf_temp
        warning "已添加$1的证书自动续期任务"
    fi
}

apply_cert() {
    warning "正在为您申请证书，您稍等..."
    certbot certonly \
    --standalone \
    --agree-tos \
    --no-eff-email \
    --email $1 \
    -d $2
    exit_cert=$(cat /etc/letsencrypt/live/$2*/fullchain.pem | grep -i -c "cert")
    exit_key=$(cat /etc/letsencrypt/live/$2*/privkey.pem | grep -i -c "key")
    if [[ ${exit_cert} -eq 0 || ${exit_key} -eq 0 ]]; then
        error "证书申请失败" && exit 1
    else
        success "证书申请成功"
        cert_update $2
    fi
}

revoke_cert() {
    warning "正在撤销$2的证书..."
    certbot revoke --cert-path /etc/letsencrypt/live/$2*/cert.pem
}

check_cert() {
    if [[ -d "/etc/letsencrypt/live/${2}*" ]]; then
        read -rp "是否撤销已有证书并重新申请？(y/[n])：" del_cert
        if [[ ${del_cert} == [yY] ]]; then
            revoke_cert $2
        else 
            exit 0
        fi
    fi
    apply_cert $1 $2
}

start() {
    read -rp "请输入注册邮箱: " email_input
    if [[ -z $email_input ]]; then
        error "邮箱不能为空" && exit 1
    fi
    read -rp "请输入域名：" domain_input
    if [[ -z ${domain_input} ]]; then
        error "域名不能为空" && exit 1
    fi
    brefore_install
    check_80
    check_cert $email_input $domain_input
 
}


menu() {
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 申请证书"
    echo " -------------"
    echo -e " ${GREEN}0.${PLAIN} 退出脚本"
    echo ""
    read -rp "请选择: " NumberInput
    case "$NumberInput" in
        1) start ;;
        *) exit 1 ;;
    esac
}

menu
