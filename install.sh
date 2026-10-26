#!/bin/bash

# ============================================
# Speedtest-X 一键安装/卸载/管理脚本 (Nginx + PHP-FPM)
# 用法: ./speedtest.sh                       # 安装并启动（交互输入端口+项目名）
#       ./speedtest.sh install 33332 myspeed # 安装（指定端口和项目名）
#       ./speedtest.sh uninstall             # 完全卸载
#       ./speedtest.sh menu                  # 弹出管理菜单
#       安装后可使用 st 命令管理
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------- 配置 ----------
PROJECT_NAME="${PROJECT_NAME:-speedtest}"
PROJECT_DIR="/www/wwwroot/$PROJECT_NAME"
LOG_FILE="/var/log/speedtest_access.log"
ST_COMMAND_PATH="/usr/local/bin/st"

# ========== 检测系统 ==========
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/alpine-release ]; then
        OS="alpine"
    else
        echo -e "${RED}无法检测操作系统${NC}"
        exit 1
    fi
}

# ========== 端口占用检测函数 ==========
check_port() {
    local port=$1
    if command -v ss &>/dev/null; then
        if ss -tlnp | grep -q ":$port "; then
            return 0
        fi
    elif command -v netstat &>/dev/null; then
        if netstat -tlnp | grep -q ":$port "; then
            return 0
        fi
    else
        if command -v lsof &>/dev/null; then
            if lsof -i :$port &>/dev/null; then
                return 0
            fi
        fi
    fi
    return 1
}

# ========== 端口输入验证函数 ==========
validate_port() {
    local port=$1
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}错误: 端口必须为数字${NC}"
        return 1
    fi
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}错误: 端口范围必须在 1-65535 之间${NC}"
        return 1
    fi
    if [ "$port" -lt 1024 ] && [ "$(id -u)" -ne 0 ]; then
        echo -e "${YELLOW}警告: 端口 1-1023 为系统保留端口，需要 root 权限${NC}"
    fi
    return 0
}

# ========== 安装 st 命令（完全独立版本）==========
install_st_command() {
    echo -e "${GREEN}安装全局命令 'st'...${NC}"
    
    # 检测并保存实际的配置信息
    local ACTUAL_PORT=""
    local ACTUAL_PHP_SOCKET=""
    local ACTUAL_PHP_FPM_SERVICE=""
    
    # 获取端口
    if [ -f "/etc/nginx/http.d/speedtest.conf" ]; then
        ACTUAL_PORT=$(grep -oP 'listen \K[0-9]+' /etc/nginx/http.d/speedtest.conf | head -1)
    elif [ -f "/etc/nginx/conf.d/speedtest.conf" ]; then
        ACTUAL_PORT=$(grep -oP 'listen \K[0-9]+' /etc/nginx/conf.d/speedtest.conf | head -1)
    elif [ -f "/etc/nginx/sites-enabled/speedtest" ]; then
        ACTUAL_PORT=$(grep -oP 'listen \K[0-9]+' /etc/nginx/sites-enabled/speedtest | head -1)
    fi
    
    # 获取 PHP socket
    if [ -f "/etc/nginx/http.d/speedtest.conf" ]; then
        ACTUAL_PHP_SOCKET=$(grep -oP 'fastcgi_pass \K[^;]+' /etc/nginx/http.d/speedtest.conf | head -1)
    elif [ -f "/etc/nginx/conf.d/speedtest.conf" ]; then
        ACTUAL_PHP_SOCKET=$(grep -oP 'fastcgi_pass \K[^;]+' /etc/nginx/conf.d/speedtest.conf | head -1)
    fi
    
    # 检测 PHP-FPM 服务名
    if command -v rc-service &>/dev/null; then
        for svc in php-fpm php-fpm82 php-fpm83 php-fpm8 php-fpm7; do
            if rc-service $svc status 2>/dev/null | grep -q "started"; then
                ACTUAL_PHP_FPM_SERVICE=$svc
                break
            fi
        done
    elif command -v systemctl &>/dev/null; then
        ACTUAL_PHP_FPM_SERVICE=$(systemctl list-units --type=service | grep -oP 'php.*-fpm\.service' | head -1 | sed 's/\.service//')
    fi
    [ -z "$ACTUAL_PHP_FPM_SERVICE" ] && ACTUAL_PHP_FPM_SERVICE="php-fpm"
    
    # 创建完全独立的 st 命令
    cat > "$ST_COMMAND_PATH" << 'STEOF'
#!/bin/bash
# ============================================
# Speedtest-X 管理命令 (独立版本)
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 硬编码配置（安装时写入）
STEOF
    
    # 动态写入配置（支持自定义项目名）
    cat >> "$ST_COMMAND_PATH" << EOF
PROJECT_NAME="${PROJECT_NAME}"
PROJECT_DIR="${PROJECT_DIR}"
PORT="${ACTUAL_PORT:-unknown}"
PHP_FPM_SERVICE="${ACTUAL_PHP_FPM_SERVICE:-php-fpm}"
EOF
    
    # 继续写入函数定义
    cat >> "$ST_COMMAND_PATH" << 'STEOF'

# ========== 显示菜单 ==========
show_menu() {
    clear
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║        Speedtest-X 管理菜单           ║${NC}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}  1)${NC} ${BOLD}启动服务${NC}"
    echo -e "${YELLOW}  2)${NC} ${BOLD}重启服务${NC}"
    echo -e "${BLUE}  3)${NC} ${BOLD}查看状态${NC}"
    echo -e "${RED}  4)${NC} ${BOLD}停止服务${NC}"
    echo -e "${CYAN}  5)${NC} ${BOLD}查看日志${NC}"
    echo -e "${CYAN}  6)${NC} ${BOLD}配置信息${NC}"
    echo -e "${RED}  7)${NC} ${BOLD}卸载程序${NC}"
    echo ""
    echo -e "${BOLD}  0)${NC} ${BOLD}退出${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    read -p "$(echo -e ${BOLD}"请选择操作 [0-7]: "${NC})" choice
    
    case $choice in
        1) start_services ;;
        2) restart_services ;;
        3) show_status ;;
        4) stop_services ;;
        5) show_logs ;;
        6) show_config ;;
        7) uninstall_speedtest ;;
        0) echo -e "${GREEN}再见！${NC}"; exit 0 ;;
        *) echo -e "${RED}无效选择！${NC}"; sleep 1; show_menu ;;
    esac
}

# ========== 端口检测 ==========
check_port() {
    local port=$1
    if command -v ss &>/dev/null; then
        ss -tlnp | grep -q ":$port "
        return $?
    elif command -v netstat &>/dev/null; then
        netstat -tlnp | grep -q ":$port "
        return $?
    elif command -v lsof &>/dev/null; then
        lsof -i :$port &>/dev/null
        return $?
    fi
    return 1
}

# ========== 启动服务 ==========
start_services() {
    echo -e "${GREEN}正在启动服务...${NC}"
    
    if [ ! -f "$PROJECT_DIR/index.html" ] && [ ! -f "$PROJECT_DIR/index.php" ]; then
        echo -e "${RED}错误: Speedtest-X 未安装！${NC}"
        sleep 2
        show_menu
        return
    fi
    
    # 启动 PHP-FPM
    if command -v rc-service &>/dev/null; then
        rc-service $PHP_FPM_SERVICE start 2>/dev/null || {
            for svc in php-fpm php-fpm82 php-fpm83 php-fpm8; do
                rc-service $svc start 2>/dev/null && break
            done
        }
    elif command -v systemctl &>/dev/null; then
        systemctl start $PHP_FPM_SERVICE 2>/dev/null || systemctl start php*-fpm 2>/dev/null
    else
        service $PHP_FPM_SERVICE start 2>/dev/null || service php-fpm start 2>/dev/null
    fi
    
    # 启动 Nginx
    if command -v rc-service &>/dev/null; then
        rc-service nginx start
    elif command -v systemctl &>/dev/null; then
        systemctl start nginx
    else
        service nginx start
    fi
    
    sleep 1
    echo -e "${GREEN}服务已启动！${NC}"
    show_status
    echo ""
    read -p "按回车键返回菜单..." 
    show_menu
}

# ========== 停止服务 ==========
stop_services() {
    echo -e "${YELLOW}正在停止服务...${NC}"
    
    # 停止 PHP-FPM
    if command -v rc-service &>/dev/null; then
        rc-service $PHP_FPM_SERVICE stop 2>/dev/null || {
            for svc in php-fpm php-fpm82 php-fpm83 php-fpm8; do
                rc-service $svc stop 2>/dev/null
            done
        }
    elif command -v systemctl &>/dev/null; then
        systemctl stop $PHP_FPM_SERVICE 2>/dev/null || systemctl stop php*-fpm 2>/dev/null
    else
        service $PHP_FPM_SERVICE stop 2>/dev/null || service php-fpm stop 2>/dev/null
    fi
    
    # 停止 Nginx
    if command -v rc-service &>/dev/null; then
        rc-service nginx stop
    elif command -v systemctl &>/dev/null; then
        systemctl stop nginx
    else
        service nginx stop
    fi
    
    sleep 1
    echo -e "${GREEN}服务已停止！${NC}"
    show_status
    echo ""
    read -p "按回车键返回菜单..." 
    show_menu
}

# ========== 重启服务 ==========
restart_services() {
    echo -e "${YELLOW}正在重启服务...${NC}"
    
    if [ ! -f "$PROJECT_DIR/index.html" ] && [ ! -f "$PROJECT_DIR/index.php" ]; then
        echo -e "${RED}错误: Speedtest-X 未安装！${NC}"
        sleep 2
        show_menu
        return
    fi
    
    # 重启 PHP-FPM
    if command -v rc-service &>/dev/null; then
        rc-service $PHP_FPM_SERVICE restart 2>/dev/null || {
            for svc in php-fpm php-fpm82 php-fpm83 php-fpm8; do
                rc-service $svc restart 2>/dev/null && break
            done
        }
    elif command -v systemctl &>/dev/null; then
        systemctl restart $PHP_FPM_SERVICE 2>/dev/null || systemctl restart php*-fpm 2>/dev/null
    else
        service $PHP_FPM_SERVICE restart 2>/dev/null || service php-fpm restart 2>/dev/null
    fi
    
    # 重启 Nginx
    if command -v rc-service &>/dev/null; then
        rc-service nginx restart
    elif command -v systemctl &>/dev/null; then
        systemctl restart nginx
    else
        service nginx restart
    fi
    
    sleep 1
    echo -e "${GREEN}服务已重启！${NC}"
    show_status
    echo ""
    read -p "按回车键返回菜单..." 
    show_menu
}

# ========== 查看状态 ==========
show_status() {
    echo -e "\n${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}          Speedtest-X 运行状态${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}\n"
    
    # Nginx 状态
    echo -e "${BOLD}Nginx:${NC}"
    if pgrep -x "nginx" > /dev/null 2>&1; then
        echo -e "  ${GREEN}● 运行中${NC}  PID: $(pgrep -x nginx | head -1)  进程: $(pgrep -cx nginx)"
    else
        echo -e "  ${RED}● 未运行${NC}"
    fi
    
    # PHP-FPM 状态
    echo -e "${BOLD}PHP-FPM:${NC}"
    if pgrep -f "php-fpm" > /dev/null 2>&1; then
        echo -e "  ${GREEN}● 运行中${NC}  PID: $(pgrep -f 'php-fpm' | head -1)  进程: $(pgrep -cf 'php-fpm')"
    else
        echo -e "  ${RED}● 未运行${NC}"
    fi
    
    # 端口监听
    echo -e "${BOLD}端口 ${PORT}:${NC}"
    if [ -n "$PORT" ] && [ "$PORT" != "unknown" ]; then
        if check_port $PORT; then
            echo -e "  ${GREEN}● 监听中${NC}"
        else
            echo -e "  ${RED}● 未监听${NC}"
        fi
    else
        echo -e "  ${YELLOW}● 未知${NC}"
    fi
    
    # 访问测试
    if [ -n "$PORT" ] && [ "$PORT" != "unknown" ]; then
        echo -e "${BOLD}访问测试 (/${PROJECT_NAME}/):${NC}"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 "http://127.0.0.1:$PORT/${PROJECT_NAME}/" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ]; then
            echo -e "  ${GREEN}● 正常${NC} (HTTP $HTTP_CODE)"
        elif [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
            echo -e "  ${YELLOW}● HTTP $HTTP_CODE${NC}"
        else
            echo -e "  ${RED}● 无法访问${NC}"
        fi
    fi
    
    # 系统资源
    echo -e "\n${BOLD}系统资源:${NC}"
    if command -v free &>/dev/null; then
        MEM=$(free -m | awk '/^Mem:/{printf "%.1f%%", $3/$2*100}')
        echo -e "  内存使用: ${MEM}"
    fi
    
    # 项目大小
    if [ -d "$PROJECT_DIR" ]; then
        DISK=$(du -sh $PROJECT_DIR 2>/dev/null | awk '{print $1}')
        echo -e "  项目大小: ${DISK}"
    fi
    
    echo -e "\n${BOLD}${CYAN}════════════════════════════════════════${NC}\n"
}

# ========== 查看日志 ==========
show_logs() {
    clear
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║           日志查看菜单                 ║${NC}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}  1)${NC} 访问日志 (最近20行)"
    echo -e "${YELLOW}  2)${NC} 错误日志 (最近20行)"
    echo -e "${BLUE}  3)${NC} Nginx 系统错误日志"
    echo -e "${RED}  4)${NC} 实时监控访问日志"
    echo -e "${CYAN}  5)${NC} 查看全部访问日志"
    echo ""
    echo -e "${BOLD}  0)${NC} 返回主菜单"
    echo ""
    
    read -p "$(echo -e ${BOLD}"请选择 [0-5]: "${NC})" log_choice
    
    case $log_choice in
        1)
            echo -e "\n${BOLD}最近20行访问日志:${NC}"
            if [ -f "/var/log/nginx/speedtest_access.log" ]; then
                tail -20 /var/log/nginx/speedtest_access.log
            else
                echo -e "${RED}日志文件不存在${NC}"
            fi
            ;;
        2)
            echo -e "\n${BOLD}最近20行错误日志:${NC}"
            if [ -f "/var/log/nginx/speedtest_error.log" ]; then
                tail -20 /var/log/nginx/speedtest_error.log
            else
                echo -e "${RED}日志文件不存在${NC}"
            fi
            ;;
        3)
            echo -e "\n${BOLD}最近20行 Nginx 错误日志:${NC}"
            if [ -f "/var/log/nginx/error.log" ]; then
                tail -20 /var/log/nginx/error.log
            else
                echo -e "${RED}日志文件不存在${NC}"
            fi
            ;;
        4)
            echo -e "${YELLOW}实时监控访问日志 (Ctrl+C 退出)...${NC}"
            if [ -f "/var/log/nginx/speedtest_access.log" ]; then
                tail -f /var/log/nginx/speedtest_access.log
            else
                echo -e "${RED}日志文件不存在${NC}"
                sleep 2
            fi
            ;;
        5)
            echo -e "\n${BOLD}全部访问日志:${NC}"
            if [ -f "/var/log/nginx/speedtest_access.log" ]; then
                less /var/log/nginx/speedtest_access.log
            else
                echo -e "${RED}日志文件不存在${NC}"
                sleep 2
            fi
            ;;
        0)
            show_menu
            return
            ;;
        *)
            echo -e "${RED}无效选择！${NC}"
            sleep 1
            ;;
    esac
    
    echo ""
    read -p "按回车键继续..." 
    show_logs
}

# ========== 显示配置信息 ==========
show_config() {
    clear
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║         Speedtest-X 配置信息          ║${NC}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════╝${NC}\n"
    
    # 获取 IP
    IP=$(curl -s -m 3 4.ipw.cn 2>/dev/null || curl -s -m 3 ipinfo.io/ip 2>/dev/null || echo "未知")
    
    echo -e "${BOLD}访问地址:${NC}"
    echo -e "  🌐 http://${IP}:${PORT}/${PROJECT_NAME}/"
    echo -e "  🏠 http://localhost:${PORT}/${PROJECT_NAME}/"
    echo ""
    echo -e "${BOLD}项目名称:${NC} ${PROJECT_NAME}"
    echo -e "${BOLD}项目目录:${NC} ${PROJECT_DIR}"
    echo -e "${BOLD}监听端口:${NC} ${PORT}"
    echo ""
    
    # 显示 Nginx 配置
    CONF_FILE=""
    if [ -f "/etc/nginx/http.d/speedtest.conf" ]; then
        CONF_FILE="/etc/nginx/http.d/speedtest.conf"
    elif [ -f "/etc/nginx/conf.d/speedtest.conf" ]; then
        CONF_FILE="/etc/nginx/conf.d/speedtest.conf"
    elif [ -f "/etc/nginx/sites-enabled/speedtest" ]; then
        CONF_FILE="/etc/nginx/sites-enabled/speedtest"
    fi
    
    if [ -n "$CONF_FILE" ]; then
        echo -e "${BOLD}配置文件:${NC} ${CONF_FILE}"
        echo -e "${BOLD}PHP Socket:${NC} $(grep fastcgi_pass $CONF_FILE | awk '{print $2}' | tr -d ';')"
    fi
    
    echo ""
    
    # 版本信息
    if command -v nginx &>/dev/null; then
        echo -e "${BOLD}Nginx:${NC} $(nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+')"
    fi
    if command -v php &>/dev/null; then
        echo -e "${BOLD}PHP:${NC} $(php -v 2>/dev/null | head -1 | grep -oP 'PHP \K[0-9.]+')"
    fi
    
    echo ""
    read -p "按回车键返回菜单..." 
    show_menu
}

# ========== 卸载程序 ==========
uninstall_speedtest() {
    clear
    echo -e "${RED}${BOLD}╔════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║          警告：即将卸载！             ║${NC}"
    echo -e "${RED}${BOLD}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}这将删除:${NC}"
    echo -e "  - Speedtest-X 项目文件 (${PROJECT_DIR})"
    echo -e "  - Nginx 配置文件"
    echo -e "  - st 管理命令"
    echo ""
    
    read -p "$(echo -e ${RED}"确认卸载？输入 YES 继续: "${NC})" confirm
    
    if [ "$confirm" != "YES" ]; then
        echo -e "${GREEN}已取消卸载${NC}"
        sleep 1
        show_menu
        return
    fi
    
    echo -e "${YELLOW}正在卸载...${NC}"
    
    # 停止服务
    if command -v rc-service &>/dev/null; then
        rc-service nginx stop 2>/dev/null
        for svc in php-fpm php-fpm82 php-fpm83 php-fpm8; do
            rc-service $svc stop 2>/dev/null
        done
    elif command -v systemctl &>/dev/null; then
        systemctl stop nginx 2>/dev/null
        systemctl stop php*-fpm 2>/dev/null
    else
        service nginx stop 2>/dev/null
        service php-fpm stop 2>/dev/null
    fi
    
    # 删除配置文件
    rm -f /etc/nginx/http.d/speedtest.conf
    rm -f /etc/nginx/conf.d/speedtest.conf
    rm -f /etc/nginx/sites-available/speedtest
    rm -f /etc/nginx/sites-enabled/speedtest
    
    # 重载 Nginx
    if command -v nginx &>/dev/null; then
        nginx -s reload 2>/dev/null || true
    fi
    
    # 删除项目
    rm -rf "$PROJECT_DIR"
    
    # 删除日志
    rm -f /var/log/nginx/speedtest_access.log
    rm -f /var/log/nginx/speedtest_error.log
    
    # 删除自己
    rm -f /usr/local/bin/st
    
    # 询问是否删除 Nginx + PHP
    echo ""
    read -p "是否同时卸载 Nginx 和 PHP？(y/N): " remove_all
    
    if [[ "$remove_all" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}卸载 Nginx 和 PHP...${NC}"
        
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            case $ID in
                alpine)
                    apk del --purge nginx php* 2>/dev/null
                    ;;
                ubuntu|debian)
                    apt-get purge -y nginx php* 2>/dev/null
                    apt-get autoremove -y 2>/dev/null
                    ;;
                centos|rhel|fedora|rocky|almalinux)
                    if command -v dnf &>/dev/null; then
                        dnf remove -y nginx php* 2>/dev/null
                    else
                        yum remove -y nginx php* 2>/dev/null
                    fi
                    ;;
            esac
        fi
    fi
    
    echo -e "${GREEN}卸载完成！${NC}"
    exit 0
}

# ========== 主程序 ==========
# 检查 root 权限
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 请使用 root 权限运行此命令${NC}"
    echo -e "${YELLOW}用法: sudo st${NC}"
    exit 1
fi

# 如果没有参数，显示菜单
show_menu
STEOF
    
    chmod +x "$ST_COMMAND_PATH"
    
    echo -e "${GREEN}✓ 全局命令 'st' 安装成功${NC}"
    echo -e "${YELLOW}现在可以在任意位置使用 'st' 命令管理 Speedtest-X${NC}"
}

# ========== 卸载函数 ==========
uninstall() {
    # 从 st 命令反读实际 PROJECT_DIR（支持自定义名字）
    if [ -f "$ST_COMMAND_PATH" ]; then
        _PD=$(grep -oP '^PROJECT_DIR="\K[^"]+' "$ST_COMMAND_PATH" | head -1)
        [ -n "$_PD" ] && PROJECT_DIR="$_PD"
        _PN=$(grep -oP '^PROJECT_NAME="\K[^"]+' "$ST_COMMAND_PATH" | head -1)
        [ -n "$_PN" ] && PROJECT_NAME="$_PN"
    fi

    echo -e "${YELLOW}正在卸载 Speedtest-X...${NC}"
    echo -e "${YELLOW}项目目录: $PROJECT_DIR${NC}"

    # 停止服务
    echo -e "${YELLOW}停止相关服务...${NC}"
    if command -v rc-service &>/dev/null; then
        rc-service nginx stop 2>/dev/null || true
        rc-service php-fpm stop 2>/dev/null || true
        rc-service php-fpm82 stop 2>/dev/null || true
        rc-service php-fpm83 stop 2>/dev/null || true
    elif command -v systemctl &>/dev/null; then
        systemctl stop nginx 2>/dev/null || true
        systemctl stop php-fpm 2>/dev/null || true
        systemctl stop php*-fpm 2>/dev/null || true
    else
        service nginx stop 2>/dev/null || true
        service php-fpm stop 2>/dev/null || true
    fi

    # 删除自启动项
    echo -e "${YELLOW}删除自启动项...${NC}"
    if command -v rc-update &>/dev/null; then
        rc-update del nginx default 2>/dev/null || true
        rc-update del php-fpm default 2>/dev/null || true
        rc-update del php-fpm82 default 2>/dev/null || true
        rc-update del php-fpm83 default 2>/dev/null || true
    elif command -v systemctl &>/dev/null; then
        systemctl disable nginx 2>/dev/null || true
        systemctl disable php-fpm 2>/dev/null || true
        systemctl disable php*-fpm 2>/dev/null || true
    elif command -v chkconfig &>/dev/null; then
        chkconfig nginx off 2>/dev/null || true
        chkconfig php-fpm off 2>/dev/null || true
    elif command -v update-rc.d &>/dev/null; then
        update-rc.d nginx remove 2>/dev/null || true
        update-rc.d php-fpm remove 2>/dev/null || true
        update-rc.d php*-fpm remove 2>/dev/null || true
    fi

    # 删除 Nginx 站点配置
    echo -e "${YELLOW}删除配置文件...${NC}"
    rm -f /etc/nginx/http.d/speedtest.conf 2>/dev/null
    rm -f /etc/nginx/conf.d/speedtest.conf 2>/dev/null
    rm -f /etc/nginx/sites-available/speedtest 2>/dev/null
    rm -f /etc/nginx/sites-enabled/speedtest 2>/dev/null

    # 重载 Nginx
    if command -v nginx &>/dev/null; then
        if command -v rc-service &>/dev/null; then
            rc-service nginx reload 2>/dev/null || true
        elif command -v systemctl &>/dev/null; then
            systemctl reload nginx 2>/dev/null || true
        fi
    fi

    # 删除项目目录
    rm -rf "$PROJECT_DIR"

    # 删除 st 命令
    rm -f "$ST_COMMAND_PATH"

    # 询问是否卸载 Nginx + PHP
    echo -e "${YELLOW}是否同时卸载 Nginx 和 PHP？${NC}"
    echo -e "${YELLOW}这将删除所有相关软件包！${NC}"
    
    if [ -t 0 ]; then
        read -p "请输入 (y/N): " REMOVE_NGINX
    elif [ -e /dev/tty ]; then
        read -p "请输入 (y/N): " REMOVE_NGINX < /dev/tty
    else
        echo -e "${YELLOW}无法获取输入，默认不卸载 Nginx 和 PHP${NC}"
        REMOVE_NGINX="n"
    fi
    
    if [[ "$REMOVE_NGINX" =~ ^[Yy]$ ]]; then
        case $OS in
            alpine)
                apk del --purge nginx php php-fpm php-mbstring php-xml php-curl php-zip php-gd php-json php-openssl php-ctype 2>/dev/null
                ;;
            ubuntu|debian)
                apt-get purge -y nginx php-fpm php-cli php-mbstring php-xml php-curl php-zip php-gd php-ctype 2>/dev/null
                apt-get autoremove -y 2>/dev/null
                ;;
            centos|rhel|fedora|rocky|almalinux)
                if command -v dnf &>/dev/null; then
                    dnf remove -y nginx php-fpm php-cli php-mbstring php-xml php-curl php-zip php-gd 2>/dev/null
                else
                    yum remove -y nginx php-fpm php-cli php-mbstring php-xml php-curl php-zip php-gd 2>/dev/null
                fi
                ;;
        esac
        echo -e "${GREEN}Nginx 和 PHP 已卸载${NC}"
    else
        echo -e "${GREEN}保留 Nginx 和 PHP${NC}"
    fi

    # 清理日志文件
    rm -f /var/log/nginx/speedtest_access.log 2>/dev/null
    rm -f /var/log/nginx/speedtest_error.log 2>/dev/null

    echo -e "${GREEN}卸载完成！${NC}"
    exit 0
}

# ========== 显示菜单（安装脚本中的）==========
show_menu_installer() {
    clear
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║        Speedtest-X 管理菜单           ║${NC}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}  1)${NC} ${BOLD}启动服务${NC}"
    echo -e "${YELLOW}  2)${NC} ${BOLD}重启服务${NC}"
    echo -e "${BLUE}  3)${NC} ${BOLD}查看状态${NC}"
    echo -e "${RED}  4)${NC} ${BOLD}卸载程序${NC}"
    echo ""
    echo -e "${BOLD}  0)${NC} ${BOLD}退出${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    read -p "$(echo -e ${BOLD}"请选择操作 [0-4]: "${NC})" choice
    
    case $choice in
        1)
            # 启动服务
            echo -e "${GREEN}正在启动服务...${NC}"
            if command -v rc-service &>/dev/null; then
                rc-service php-fpm start 2>/dev/null || rc-service php-fpm82 start 2>/dev/null || rc-service php-fpm83 start 2>/dev/null
                rc-service nginx start
            elif command -v systemctl &>/dev/null; then
                systemctl start php-fpm 2>/dev/null || systemctl start php*-fpm 2>/dev/null
                systemctl start nginx
            else
                service php-fpm start 2>/dev/null
                service nginx start
            fi
            echo -e "${GREEN}服务已启动！${NC}"
            sleep 1
            show_menu_installer
            ;;
        2)
            # 重启服务
            echo -e "${YELLOW}正在重启服务...${NC}"
            if command -v rc-service &>/dev/null; then
                rc-service php-fpm restart 2>/dev/null || rc-service php-fpm82 restart 2>/dev/null || rc-service php-fpm83 restart 2>/dev/null
                rc-service nginx restart
            elif command -v systemctl &>/dev/null; then
                systemctl restart php-fpm 2>/dev/null || systemctl restart php*-fpm 2>/dev/null
                systemctl restart nginx
            else
                service php-fpm restart 2>/dev/null
