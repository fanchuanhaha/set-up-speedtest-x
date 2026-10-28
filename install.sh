#!/bin/bash

# ============================================
# Speedtest-X 一键安装/卸载/管理脚本 (Nginx + PHP-FPM)
# 用法: ./speedtest.sh                       # 安装（交互输入端口+文件夹）
#       ./speedtest.sh install 33332 abc     # 安装到 /www/wwwroot/speedtest/abc/
#       ./speedtest.sh install 33332         # 安装到 /www/wwwroot/speedtest/（根）
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
BASE_DIR="/www/wwwroot/speedtest"
PROJECT_NAME=""
PROJECT_DIR="$BASE_DIR"
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

# ========== 端口检测 ==========
check_port() {
    local port=$1
    if command -v ss &>/dev/null; then
        if ss -tlnp | grep -q ":$port "; then return 0; fi
    elif command -v netstat &>/dev/null; then
        if netstat -tlnp | grep -q ":$port "; then return 0; fi
    else
        if command -v lsof &>/dev/null; then
            if lsof -i :$port &>/dev/null; then return 0; fi
        fi
    fi
    return 1
}

validate_port() {
    local port=$1
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}错误: 端口必须为数字${NC}"; return 1
    fi
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}错误: 端口范围必须在 1-65535 之间${NC}"; return 1
    fi
    return 0
}

# ========== 安装 st 命令 ==========
install_st_command() {
    echo -e "${GREEN}安装全局命令 'st'...${NC}"
    
    local ACTUAL_PORT=""
    local ACTUAL_PHP_FPM_SERVICE=""
    
    if [ -f "/etc/nginx/http.d/speedtest.conf" ]; then
        ACTUAL_PORT=$(grep -oP 'listen \K[0-9]+' /etc/nginx/http.d/speedtest.conf | head -1)
    elif [ -f "/etc/nginx/conf.d/speedtest.conf" ]; then
        ACTUAL_PORT=$(grep -oP 'listen \K[0-9]+' /etc/nginx/conf.d/speedtest.conf | head -1)
    elif [ -f "/etc/nginx/sites-enabled/speedtest" ]; then
        ACTUAL_PORT=$(grep -oP 'listen \K[0-9]+' /etc/nginx/sites-enabled/speedtest | head -1)
    fi
    
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

    cat > "$ST_COMMAND_PATH" << 'STEOF'
#!/bin/bash
# ============================================
# Speedtest-X 管理命令
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ST_COMMAND_PATH="/usr/local/bin/st"

STEOF

    cat >> "$ST_COMMAND_PATH" << EOF
BASE_DIR="${BASE_DIR}"
PROJECT_NAME="${PROJECT_NAME}"
PROJECT_DIR="${PROJECT_DIR}"
PORT="${ACTUAL_PORT:-unknown}"
PHP_FPM_SERVICE="${ACTUAL_PHP_FPM_SERVICE:-php-fpm}"
EOF

    cat >> "$ST_COMMAND_PATH" << 'STEOF'

if [ -z "$PROJECT_NAME" ]; then URL_PATH="/"; else URL_PATH="/$PROJECT_NAME/"; fi

# ========== 辅助 ==========
find_nginx_conf() {
    if [ -f "/etc/nginx/http.d/speedtest.conf" ]; then
        echo "/etc/nginx/http.d/speedtest.conf"
    elif [ -f "/etc/nginx/conf.d/speedtest.conf" ]; then
        echo "/etc/nginx/conf.d/speedtest.conf"
    elif [ -f "/etc/nginx/sites-enabled/speedtest" ]; then
        echo "/etc/nginx/sites-enabled/speedtest"
    fi
}

reload_nginx() {
    if command -v rc-service &>/dev/null; then
        rc-service nginx reload 2>/dev/null || rc-service nginx restart 2>/dev/null
    elif command -v systemctl &>/dev/null; then
        systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null
    else
        service nginx reload 2>/dev/null || service nginx restart 2>/dev/null
    fi
}

check_port() {
    local port=$1
    if command -v ss &>/dev/null; then
        ss -tlnp | grep -q ":$port "; return $?
    elif command -v netstat &>/dev/null; then
        netstat -tlnp | grep -q ":$port "; return $?
    elif command -v lsof &>/dev/null; then
        lsof -i :$port &>/dev/null; return $?
    fi
    return 1
}

# ========== 菜单 ==========
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
    echo -e "${BOLD}  7)${NC} ${BOLD}修改端口${NC}"
    echo -e "${BOLD}  8)${NC} ${BOLD}修改目录${NC}"
    echo -e "${RED}  9)${NC} ${BOLD}卸载程序${NC}"
    echo ""
    echo -e "${BOLD}  0)${NC} ${BOLD}退出${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p "$(echo -e ${BOLD}"请选择操作 [0-9]: "${NC})" choice
    case $choice in
        1) start_services ;;
        2) restart_services ;;
        3) show_status ;;
        4) stop_services ;;
        5) show_logs ;;
        6) show_config ;;
        7) change_port ;;
        8) change_dir ;;
        9) uninstall_speedtest ;;
        0) echo -e "${GREEN}再见！${NC}"; exit 0 ;;
        *) echo -e "${RED}无效选择！${NC}"; sleep 1; show_menu ;;
    esac
}

# ========== 修改端口 ==========
change_port() {
    clear
    echo -e "${CYAN}${BOLD}─── 修改端口 ───${NC}"
    echo -e "当前端口: ${GREEN}$PORT${NC}"
    echo ""
    read -p "请输入新端口号 (1-65535): " NEW_PORT
    if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -lt 1 ] || [ "$NEW_PORT" -gt 65535 ]; then
        echo -e "${RED}端口无效${NC}"; sleep 2; return
    fi
    if [ "$NEW_PORT" = "$PORT" ]; then
        echo -e "${YELLOW}端口未变${NC}"; sleep 1; return
    fi
    if check_port $NEW_PORT; then
        echo -e "${RED}端口 $NEW_PORT 已被占用${NC}"; sleep 2; return
    fi
    
    CONF_FILE=$(find_nginx_conf)
    if [ -z "$CONF_FILE" ]; then
        echo -e "${RED}找不到 Nginx 配置文件${NC}"; sleep 2; return
    fi
    
    cp "$CONF_FILE" "${CONF_FILE}.bak"
    sed -i "s/^\(\s*\)listen\s\+[0-9]\+;/\1listen $NEW_PORT;/" "$CONF_FILE"
    
    if ! nginx -t 2>/dev/null; then
        echo -e "${RED}Nginx 配置测试失败，回滚${NC}"
        mv "${CONF_FILE}.bak" "$CONF_FILE"
        sleep 2; return
    fi
    rm -f "${CONF_FILE}.bak"
    
    reload_nginx
    sleep 1
    
    sed -i "s/^PORT=.*/PORT=\"$NEW_PORT\"/" "$ST_COMMAND_PATH"
    OLD_PORT=$PORT
    PORT=$NEW_PORT
    
    echo -e "${GREEN}✓ 端口已从 $OLD_PORT 修改为 $PORT${NC}"
    echo -e "${CYAN}新访问地址: http://IP:$PORT$URL_PATH${NC}"
    if check_port $PORT; then
        echo -e "${GREEN}✓ 新端口监听正常${NC}"
    else
        echo -e "${YELLOW}⚠ 新端口未监听，请检查: $CONF_FILE${NC}"
    fi
    echo ""
    read -p "按回车键返回菜单..."
    show_menu
}

# ========== 修改目录 ==========
change_dir() {
    clear
    echo -e "${CYAN}${BOLD}─── 修改目录 ───${NC}"
    if [ -z "$PROJECT_NAME" ]; then
        echo -e "当前部署: ${GREEN}根目录${NC} ($BASE_DIR)"
        echo -e "访问地址: http://IP:$PORT/"
    else
        echo -e "当前部署: ${GREEN}子目录${NC} ($BASE_DIR/$PROJECT_NAME)"
        echo -e "访问地址: http://IP:$PORT/$PROJECT_NAME/"
    fi
    echo ""
    read -p "请输入新目录名（直接回车=根目录）: " NEW_NAME
    
    if [ -n "$NEW_NAME" ] && [[ ! "$NEW_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}目录名只能包含字母、数字、下划线、连字符${NC}"; sleep 2; return
    fi
    if [ "$NEW_NAME" = "$PROJECT_NAME" ]; then
        echo -e "${YELLOW}目录未变${NC}"; sleep 1; return
    fi
    if [ -n "$NEW_NAME" ] && [ -d "${BASE_DIR}/${NEW_NAME}" ]; then
        echo -e "${RED}目标目录 ${BASE_DIR}/${NEW_NAME} 已存在${NC}"; sleep 2; return
    fi
    
    CONF_FILE=$(find_nginx_conf)
    if [ -z "$CONF_FILE" ]; then
        echo -e "${RED}找不到 Nginx 配置文件${NC}"; sleep 2; return
    fi
    
    PHP_SOCKET=$(grep -oP 'fastcgi_pass \K[^;]+' "$CONF_FILE" | head -1 | sed 's/;//')
    [ -z "$PHP_SOCKET" ] && PHP_SOCKET="unix:/run/php/php-fpm.sock"
    
    cp "$CONF_FILE" "${CONF_FILE}.bak"
    OLD_PROJECT_NAME="$PROJECT_NAME"
    OLD_PROJECT_DIR="$PROJECT_DIR"
    
    echo -e "${YELLOW}移动文件...${NC}"
    mkdir -p "$BASE_DIR"
    if [ -z "$OLD_PROJECT_NAME" ] && [ -n "$NEW_NAME" ]; then
        mkdir -p "${BASE_DIR}/${NEW_NAME}"
        find "$BASE_DIR" -mindepth 1 -maxdepth 1 ! -name "$NEW_NAME" -exec mv {} "${BASE_DIR}/${NEW_NAME}/" \; 2>/dev/null
    elif [ -n "$OLD_PROJECT_NAME" ] && [ -z "$NEW_NAME" ]; then
        find "${BASE_DIR}/${OLD_PROJECT_NAME}" -mindepth 1 -maxdepth 1 -exec mv {} "$BASE_DIR/" \; 2>/dev/null
        rmdir "${BASE_DIR}/${OLD_PROJECT_NAME}" 2>/dev/null || true
    else
        mv "${BASE_DIR}/${OLD_PROJECT_NAME}" "${BASE_DIR}/${NEW_NAME}"
    fi
    
    PROJECT_NAME="$NEW_NAME"
    if [ -z "$PROJECT_NAME" ]; then
        PROJECT_DIR="$BASE_DIR"; URL_PATH="/"
    else
        PROJECT_DIR="${BASE_DIR}/${PROJECT_NAME}"; URL_PATH="/$PROJECT_NAME/"
    fi
    
    echo -e "${YELLOW}更新 Nginx 配置...${NC}"
    if [ -z "$PROJECT_NAME" ]; then
        cat > "$CONF_FILE" << NGINXEOF
server {
    listen ${PORT};
    server_name _;

    root ${BASE_DIR};
    index index.html index.htm index.php;

    access_log /var/log/nginx/speedtest_access.log;
    error_log /var/log/nginx/speedtest_error.log;

    client_max_body_size 20M;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass ${PHP_SOCKET};
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
NGINXEOF
    else
        cat > "$CONF_FILE" << NGINXEOF
server {
    listen ${PORT};
    server_name _;

    root ${BASE_DIR};
    index index.html index.htm index.php;

    access_log /var/log/nginx/speedtest_access.log;
    error_log /var/log/nginx/speedtest_error.log;

    client_max_body_size 20M;

    location = / {
        return 301 /${PROJECT_NAME}/;
    }

    location = /${PROJECT_NAME} {
        return 301 /${PROJECT_NAME}/;
    }

    location /${PROJECT_NAME}/ {
        try_files \$uri \$uri/ /${PROJECT_NAME}/index.php?\$args;
    }

    location ~ ^/${PROJECT_NAME}/.+\.php\$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass ${PHP_SOCKET};
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
NGINXEOF
    fi
    
    if ! nginx -t 2>/dev/null; then
        echo -e "${RED}Nginx 配置测试失败，回滚${NC}"
        mv "${CONF_FILE}.bak" "$CONF_FILE"
        echo -e "${YELLOW}回滚文件...${NC}"
        if [ -z "$OLD_PROJECT_NAME" ] && [ -n "$NEW_NAME" ]; then
            find "${BASE_DIR}/${NEW_NAME}" -mindepth 1 -maxdepth 1 -exec mv {} "$BASE_DIR/" \; 2>/dev/null
            rmdir "${BASE_DIR}/${NEW_NAME}" 2>/dev/null || true
        elif [ -n "$OLD_PROJECT_NAME" ] && [ -z "$NEW_NAME" ]; then
            mkdir -p "${BASE_DIR}/${OLD_PROJECT_NAME}"
            find "$BASE_DIR" -mindepth 1 -maxdepth 1 ! -name "$OLD_PROJECT_NAME" -exec mv {} "${BASE_DIR}/${OLD_PROJECT_NAME}/" \; 2>/dev/null
        else
            mv "${BASE_DIR}/${NEW_NAME}" "${BASE_DIR}/${OLD_PROJECT_NAME}"
        fi
        PROJECT_NAME="$OLD_PROJECT_NAME"
        PROJECT_DIR="$OLD_PROJECT_DIR"
        if [ -z "$PROJECT_NAME" ]; then URL_PATH="/"; else URL_PATH="/$PROJECT_NAME/"; fi
        sleep 3; return
    fi
    rm -f "${CONF_FILE}.bak"
    
    reload_nginx
    sleep 1
    
    sed -i "s|^PROJECT_NAME=.*|PROJECT_NAME=\"$PROJECT_NAME\"|" "$ST_COMMAND_PATH"
    sed -i "s|^PROJECT_DIR=.*|PROJECT_DIR=\"$PROJECT_DIR\"|" "$ST_COMMAND_PATH"
    
    echo -e "${GREEN}✓ 目录已修改${NC}"
    echo -e "${CYAN}项目目录: $PROJECT_DIR${NC}"
    echo -e "${CYAN}访问地址: http://IP:$PORT$URL_PATH${NC}"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 "http://127.0.0.1:$PORT$URL_PATH" 2>/dev/null)
    echo -e "${CYAN}访问测试: HTTP $HTTP_CODE${NC}"
    echo ""
    read -p "按回车键返回菜单..."
    show_menu
}

# ========== 服务控制 ==========
start_services() {
    echo -e "${GREEN}正在启动服务...${NC}"
    if [ ! -f "$PROJECT_DIR/index.html" ] && [ ! -f "$PROJECT_DIR/index.php" ]; then
        echo -e "${RED}错误: Speedtest-X 未安装！${NC}"; sleep 2; show_menu; return
    fi
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
    if command -v rc-service &>/dev/null; then rc-service nginx start
    elif command -v systemctl &>/dev/null; then systemctl start nginx
    else service nginx start; fi
    sleep 1
    echo -e "${GREEN}服务已启动！${NC}"
    show_status
    echo ""; read -p "按回车键返回菜单..."
    show_menu
}

stop_services() {
    echo -e "${YELLOW}正在停止服务...${NC}"
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
    if command -v rc-service &>/dev/null; then rc-service nginx stop
    elif command -v systemctl &>/dev/null; then systemctl stop nginx
    else service nginx stop; fi
    sleep 1
    echo -e "${GREEN}服务已停止！${NC}"
    show_status
    echo ""; read -p "按回车键返回菜单..."
    show_menu
}

restart_services() {
    echo -e "${YELLOW}正在重启服务...${NC}"
    if [ ! -f "$PROJECT_DIR/index.html" ] && [ ! -f "$PROJECT_DIR/index.php" ]; then
        echo -e "${RED}错误: Speedtest-X 未安装！${NC}"; sleep 2; show_menu; return
    fi
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
    if command -v rc-service &>/dev/null; then rc-service nginx restart
    elif command -v systemctl &>/dev/null; then systemctl restart nginx
    else service nginx restart; fi
    sleep 1
    echo -e "${GREEN}服务已重启！${NC}"
    show_status
    echo ""; read -p "按回车键返回菜单..."
    show_menu
}

show_status() {
    echo -e "\n${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}          Speedtest-X 运行状态${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}\n"
    echo -e "${BOLD}Nginx:${NC}"
    if pgrep -x "nginx" > /dev/null 2>&1; then
        echo -e "  ${GREEN}● 运行中${NC}  PID: $(pgrep -x nginx | head -1)  进程: $(pgrep -cx nginx)"
    else
        echo -e "  ${RED}● 未运行${NC}"
    fi
    echo -e "${BOLD}PHP-FPM:${NC}"
    if pgrep -f "php-fpm" > /dev/null 2>&1; then
        echo -e "  ${GREEN}● 运行中${NC}  PID: $(pgrep -f 'php-fpm' | head -1)  进程: $(pgrep -cf 'php-fpm')"
    else
        echo -e "  ${RED}● 未运行${NC}"
    fi
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
    if [ -n "$PORT" ] && [ "$PORT" != "unknown" ]; then
        echo -e "${BOLD}访问测试 ($URL_PATH):${NC}"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 "http://127.0.0.1:$PORT$URL_PATH" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ]; then
            echo -e "  ${GREEN}● 正常${NC} (HTTP $HTTP_CODE)"
        elif [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
            echo -e "  ${YELLOW}● HTTP $HTTP_CODE${NC}"
        else
            echo -e "  ${RED}● 无法访问${NC}"
        fi
    fi
    echo -e "\n${BOLD}系统资源:${NC}"
    if command -v free &>/dev/null; then
        MEM=$(free -m | awk '/^Mem:/{printf "%.1f%%", $3/$2*100}')
        echo -e "  内存使用: ${MEM}"
    fi
    if [ -d "$PROJECT_DIR" ]; then
        DISK=$(du -sh $PROJECT_DIR 2>/dev/null | awk '{print $1}')
        echo -e "  项目大小: ${DISK}"
    fi
    echo -e "\n${BOLD}${CYAN}════════════════════════════════════════${NC}\n"
}

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
        1) echo -e "\n${BOLD}最近20行访问日志:${NC}"
           if [ -f "/var/log/nginx/speedtest_access.log" ]; then tail -20 /var/log/nginx/speedtest_access.log
           else echo -e "${RED}日志文件不存在${NC}"; fi ;;
        2) echo -e "\n${BOLD}最近20行错误日志:${NC}"
           if [ -f "/var/log/nginx/speedtest_error.log" ]; then tail -20 /var/log/nginx/speedtest_error.log
           else echo -e "${RED}日志文件不存在${NC}"; fi ;;
        3) echo -e "\n${BOLD}最近20行 Nginx 错误日志:${NC}"
           if [ -f "/var/log/nginx/error.log" ]; then tail -20 /var/log/nginx/error.log
           else echo -e "${RED}日志文件不存在${NC}"; fi ;;
        4) echo -e "${YELLOW}实时监控访问日志 (Ctrl+C 退出)...${NC}"
           if [ -f "/var/log/nginx/speedtest_access.log" ]; then tail -f /var/log/nginx/speedtest_access.log
           else echo -e "${RED}日志文件不存在${NC}"; sleep 2; fi ;;
        5) echo -e "\n${BOLD}全部访问日志:${NC}"
           if [ -f "/var/log/nginx/speedtest_access.log" ]; then less /var/log/nginx/speedtest_access.log
           else echo -e "${RED}日志文件不存在${NC}"; sleep 2; fi ;;
        0) show_menu; return ;;
        *) echo -e "${RED}无效选择！${NC}"; sleep 1 ;;
    esac
    echo ""; read -p "按回车键继续..."
    show_logs
}

show_config() {
    clear
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║         Speedtest-X 配置信息          ║${NC}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════╝${NC}\n"
    IP=$(curl -s -m 3 4.ipw.cn 2>/dev/null || curl -s -m 3 ipinfo.io/ip 2>/dev/null || echo "未知")
    echo -e "${BOLD}访问地址:${NC}"
    echo -e "  🌐 http://${IP}:${PORT}${URL_PATH}"
    echo -e "  🏠 http://localhost:${PORT}${URL_PATH}"
    echo ""
    if [ -z "$PROJECT_NAME" ]; then
        echo -e "${BOLD}部署方式:${NC} 根目录 (${BASE_DIR})"
    else
        echo -e "${BOLD}部署方式:${NC} 子目录 (${PROJECT_NAME})"
    fi
    echo -e "${BOLD}基础目录:${NC} ${BASE_DIR}"
    echo -e "${BOLD}项目目录:${NC} ${PROJECT_DIR}"
    echo -e "${BOLD}监听端口:${NC} ${PORT}"
    echo ""
    CONF_FILE=$(find_nginx_conf)
    if [ -n "$CONF_FILE" ]; then
        echo -e "${BOLD}配置文件:${NC} ${CONF_FILE}"
        echo -e "${BOLD}PHP Socket:${NC} $(grep fastcgi_pass $CONF_FILE | awk '{print $2}' | tr -d ';')"
    fi
    echo ""
    if command -v nginx &>/dev/null; then
        echo -e "${BOLD}Nginx:${NC} $(nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+')"
    fi
    if command -v php &>/dev/null; then
        echo -e "${BOLD}PHP:${NC} $(php -v 2>/dev/null | head -1 | grep -oP 'PHP \K[0-9.]+')"
    fi
    echo ""; read -p "按回车键返回菜单..."
    show_menu
}

uninstall_speedtest() {
    clear
    echo -e "${RED}${BOLD}╔════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║          警告：即将卸载！             ║${NC}"
    echo -e "${RED}${BOLD}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}这将删除:${NC}"
    echo -e "  - 项目目录: ${PROJECT_DIR}"
    echo -e "  - Nginx 配置文件"
    echo -e "  - st 管理命令"
    echo ""
    read -p "$(echo -e ${RED}"确认卸载？输入 YES 继续: "${NC})" confirm
    if [ "$confirm" != "YES" ]; then
        echo -e "${GREEN}已取消卸载${NC}"; sleep 1; show_menu; return
    fi
    echo -e "${YELLOW}正在卸载...${NC}"
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
    rm -f /etc/nginx/http.d/speedtest.conf
    rm -f /etc/nginx/conf.d/speedtest.conf
    rm -f /etc/nginx/sites-available/speedtest
    rm -f /etc/nginx/sites-enabled/speedtest
    if command -v nginx &>/dev/null; then nginx -s reload 2>/dev/null || true; fi

    rm -rf "$PROJECT_DIR"
    if [ -n "$PROJECT_NAME" ] && [ -d "$BASE_DIR" ] && [ -z "$(ls -A "$BASE_DIR" 2>/dev/null)" ]; then
        rmdir "$BASE_DIR" 2>/dev/null || true
    fi
    rm -f /var/log/nginx/speedtest_access.log
    rm -f /var/log/nginx/speedtest_error.log
    rm -f /usr/local/bin/st

    echo ""
    read -p "是否同时卸载 Nginx 和 PHP？(y/N): " remove_all
    if [[ "$remove_all" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}卸载 Nginx 和 PHP...${NC}"
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            case $ID in
                alpine) apk del --purge nginx php* 2>/dev/null ;;
                ubuntu|debian) apt-get purge -y nginx php* 2>/dev/null; apt-get autoremove -y 2>/dev/null ;;
                centos|rhel|fedora|rocky|almalinux)
                    if command -v dnf &>/dev/null; then dnf remove -y nginx php* 2>/dev/null
                    else yum remove -y nginx php* 2>/dev/null; fi ;;
            esac
        fi
    fi
    echo -e "${GREEN}卸载完成！${NC}"
    exit 0
}

if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 请使用 root 权限运行此命令${NC}"
    echo -e "${YELLOW}用法: sudo st${NC}"
    exit 1
fi

show_menu
STEOF

    chmod +x "$ST_COMMAND_PATH"
    echo -e "${GREEN}✓ 全局命令 'st' 安装成功${NC}"
}

# ========== 卸载函数（安装脚本内）==========
uninstall() {
    if [ -f "$ST_COMMAND_PATH" ]; then
        _BD=$(grep -oP '^BASE_DIR="\K[^"]+' "$ST_COMMAND_PATH" | head -1)
        [ -n "$_BD" ] && BASE_DIR="$_BD"
        _PD=$(grep -oP '^PROJECT_DIR="\K[^"]+' "$ST_COMMAND_PATH" | head -1)
        [ -n "$_PD" ] && PROJECT_DIR="$_PD"
        _PN=$(grep -oP '^PROJECT_NAME="\K[^"]+' "$ST_COMMAND_PATH" | head -1)
        [ -n "$_PN" ] && PROJECT_NAME="$_PN"
    fi

    echo -e "${YELLOW}正在卸载 Speedtest-X...${NC}"
    echo -e "${YELLOW}项目目录: $PROJECT_DIR${NC}"

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

    if command -v rc-update &>/dev/null; then
        rc-update del nginx default 2>/dev/null || true
        rc-update del php-fpm default 2>/dev/null || true
        rc-update del php-fpm82 default 2>/dev/null || true
        rc-update del php-fpm83 default 2>/dev/null || true
    elif command -v systemctl &>/dev/null; then
        systemctl disable nginx 2>/dev/null || true
        systemctl disable php-fpm 2>/dev/null || true
        systemctl disable php*-fpm 2>/dev/null || true
    fi

    rm -f /etc/nginx/http.d/speedtest.conf 2>/dev/null
    rm -f /etc/nginx/conf.d/speedtest.conf 2>/dev/null
    rm -f /etc/nginx/sites-available/speedtest 2>/dev/null
    rm -f /etc/nginx/sites-enabled/speedtest 2>/dev/null

    if command -v nginx &>/dev/null; then
        if command -v rc-service &>/dev/null; then rc-service nginx reload 2>/dev/null || true
        elif command -v systemctl &>/dev/null; then systemctl reload nginx 2>/dev/null || true
        fi
    fi

    rm -rf "$PROJECT_DIR"
    if [ -n "$PROJECT_NAME" ] && [ -d "$BASE_DIR" ] && [ -z "$(ls -A "$BASE_DIR" 2>/dev/null)" ]; then
        rmdir "$BASE_DIR" 2>/dev/null || true
    fi

    rm -f "$ST_COMMAND_PATH"

    echo -e "${YELLOW}是否同时卸载 Nginx 和 PHP？${NC}"
    if [ -t 0 ]; then
        read -p "请输入 (y/N): " REMOVE_NGINX
    elif [ -e /dev/tty ]; then
        read -p "请输入 (y/N): " REMOVE_NGINX < /dev/tty
    else
        REMOVE_NGINX="n"
    fi

    if [[ "$REMOVE_NGINX" =~ ^[Yy]$ ]]; then
        case $OS in
            alpine) apk del --purge nginx php php-fpm php-mbstring php-xml php-curl php-zip php-gd php-json php-openssl php-ctype 2>/dev/null ;;
            ubuntu|debian) apt-get purge -y nginx php-fpm php-cli php-mbstring php-xml php-curl php-zip php-gd php-ctype 2>/dev/null; apt-get autoremove -y 2>/dev/null ;;
            centos|rhel|fedora|rocky|almalinux)
                if command -v dnf &>/dev/null; then dnf remove -y nginx php-fpm php-cli php-mbstring php-xml php-curl php-zip php-gd 2>/dev/null
                else yum remove -y nginx php-fpm php-cli php-mbstring php-xml php-curl php-zip php-gd 2>/dev/null; fi ;;
        esac
        echo -e "${GREEN}Nginx 和 PHP 已卸载${NC}"
    else
        echo -e "${GREEN}保留 Nginx 和 PHP${NC}"
    fi

    rm -f /var/log/nginx/speedtest_access.log 2>/dev/null
    rm -f /var/log/nginx/speedtest_error.log 2>/dev/null

    echo -e "${GREEN}卸载完成！${NC}"
    exit 0
}

# ========== 安装脚本内菜单 ==========
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
            echo -e "${GREEN}服务已启动！${NC}"; sleep 1; show_menu_installer ;;
        2)
            echo -e "${YELLOW}正在重启服务...${NC}"
            if command -v rc-service &>/dev/null; then
                rc-service php-fpm restart 2>/dev/null || rc-service php-fpm82 restart 2>/dev/null || rc-service php-fpm83 restart 2>/dev/null
                rc-service nginx restart
            elif command -v systemctl &>/dev/null; then
                systemctl restart php-fpm 2>/dev/null || systemctl restart php*-fpm 2>/dev/null
                systemctl restart nginx
            else
                service php-fpm restart 2>/dev/null
                service nginx restart
            fi
            echo -e "${GREEN}服务已重启！${NC}"; sleep 1; show_menu_installer ;;
        3)
            echo -e "\n${BOLD}服务状态:${NC}"
            if pgrep -x "nginx" > /dev/null; then echo -e "${GREEN}✓ Nginx 运行中${NC}"
            else echo -e "${RED}✗ Nginx 未运行${NC}"; fi
            if pgrep -f "php-fpm" > /dev/null; then echo -e "${GREEN}✓ PHP-FPM 运行中${NC}"
            else echo -e "${RED}✗ PHP-FPM 未运行${NC}"; fi
            echo ""; read -p "按回车键返回菜单..."; show_menu_installer ;;
        4) uninstall ;;
        0) echo -e "${GREEN}再见！${NC}"; exit 0 ;;
        *) echo -e "${RED}无效选择！${NC}"; sleep 1; show_menu_installer ;;
    esac
}

# ========== 主程序 ==========
detect_os
echo -e "${GREEN}操作系统: $OS${NC}"

case "${1:-install}" in
    uninstall) uninstall ;;
    menu) show_menu_installer; exit 0 ;;
    install|"") ;;
    *)
        echo -e "${RED}未知命令: $1${NC}"
        echo -e "用法: $0 [install|uninstall|menu] [端口] [文件夹]"
        exit 1
        ;;
esac

# ========== 端口输入 ==========
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}   请输入要使用的端口号${NC}"
echo -e "${BLUE}================================${NC}"

if [ -n "$2" ] && [[ "$2" =~ ^[0-9]+$ ]]; then
    PORT=$2
    echo -e "${GREEN}使用命令行参数端口: $PORT${NC}"
else
    while true; do
        read -p "请输入端口号 (默认: 33332): " INPUT_PORT
        PORT=${INPUT_PORT:-33332}
        if validate_port "$PORT"; then break; fi
    done
fi
echo -e "${GREEN}将使用端口: $PORT${NC}"

# ========== 端口检测 ==========
echo -e "${YELLOW}检测端口 $PORT 占用情况...${NC}"
if check_port $PORT; then
    echo -e "${RED}端口 $PORT 已被占用！${NC}"
    echo -e "${YELLOW}占用详情:${NC}"
    if command -v ss &>/dev/null; then ss -tlnp | grep ":$PORT "
    elif command -v netstat &>/dev/null; then netstat -tlnp | grep ":$PORT "
    elif command -v lsof &>/dev/null; then lsof -i :$PORT
    fi
    echo -e "\n${YELLOW}请选择操作:${NC}"
    echo "  1) 终止占用进程并继续安装"
    echo "  2) 更换端口重新安装"
    echo "  3) 退出安装"
    read -p "请选择 (1/2/3): " PORT_CHOICE
    case $PORT_CHOICE in
        1)
            if command -v ss &>/dev/null; then
                PID=$(ss -tlnp | grep ":$PORT " | grep -oP 'pid=\K[0-9]+' | head -1)
            elif command -v netstat &>/dev/null; then
                PID=$(netstat -tlnp | grep ":$PORT " | awk '{print $7}' | cut -d'/' -f1)
            elif command -v lsof &>/dev/null; then
                PID=$(lsof -ti :$PORT)
            fi
            if [ -n "$PID" ]; then
                echo -e "${YELLOW}终止进程 PID: $PID${NC}"
                kill -9 $PID 2>/dev/null
                sleep 1
                if check_port $PORT; then
                    echo -e "${RED}端口 $PORT 仍然被占用${NC}"; exit 1
                else
                    echo -e "${GREEN}端口 $PORT 已释放${NC}"
                fi
            else
                echo -e "${RED}无法获取进程PID${NC}"; exit 1
            fi
            ;;
        2) exec "$0" ;;
        3) echo -e "${RED}安装终止${NC}"; exit 1 ;;
        *) echo -e "${RED}无效选择，安装终止${NC}"; exit 1 ;;
    esac
else
    echo -e "${GREEN}端口 $PORT 可用${NC}"
fi

# ========== 部署文件夹输入 ==========
if [ -n "$3" ]; then
    PROJECT_NAME=$3
    if [[ ! "$PROJECT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}错误: 文件夹名只能包含字母、数字、下划线和连字符${NC}"
        exit 1
    fi
    PROJECT_DIR="$BASE_DIR/$PROJECT_NAME"
else
    read -p "请输入部署文件夹(直接回车即可): " INPUT_NAME
    if [ -z "$INPUT_NAME" ]; then
        PROJECT_NAME=""
        PROJECT_DIR="$BASE_DIR"
    else
        if [[ ! "$INPUT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo -e "${RED}错误: 文件夹名只能包含字母、数字、下划线和连字符${NC}"
            exit 1
        fi
        PROJECT_NAME="$INPUT_NAME"
        PROJECT_DIR="$BASE_DIR/$PROJECT_NAME"
    fi
fi

if [ -z "$PROJECT_NAME" ]; then
    echo -e "${GREEN}部署方式: 根目录 -> http://IP:$PORT/${NC}"
    echo -e "${GREEN}项目目录: $PROJECT_DIR${NC}"
else
    echo -e "${GREEN}部署方式: 子目录 -> http://IP:$PORT/$PROJECT_NAME/${NC}"
    echo -e "${GREEN}项目目录: $PROJECT_DIR${NC}"
fi

# ========== 安装 Nginx 和 PHP-FPM ==========
echo -e "${GREEN}安装 Nginx 和 PHP-FPM...${NC}"

case $OS in
    alpine)
        apk add --no-cache nginx php php-fpm php-mbstring php-xml php-curl php-zip php-gd php-json php-openssl php-ctype unzip curl wget bash
        PHP_SOCKET="unix:/run/php/php-fpm.sock"
        PHP_FPM_SERVICE="php-fpm82"
        if ! rc-service $PHP_FPM_SERVICE status 2>/dev/null | grep -q "started"; then
            PHP_FPM_SERVICE="php-fpm83"
        fi
        if ! rc-service $PHP_FPM_SERVICE status 2>/dev/null | grep -q "started"; then
            PHP_FPM_SERVICE="php-fpm"
        fi
        mkdir -p /run/php /var/log/nginx
        chown nginx:nginx /run/php 2>/dev/null || true
        if ! id nginx &>/dev/null; then adduser -D -g 'nginx' nginx 2>/dev/null || true; fi
        ;;
    ubuntu|debian)
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y || true
        apt-get install -y --no-install-recommends \
            nginx php-fpm php-cli php-mbstring php-xml php-curl php-zip php-gd php-ctype \
            unzip curl wget
        PHP_FPM_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)
        if [ -z "$PHP_FPM_VERSION" ]; then
            PHP_FPM_VERSION=$(ls /etc/php/*/fpm/php-fpm.conf 2>/dev/null | head -1 | sed 's|/etc/php/\(.*\)/fpm/php-fpm.conf|\1|')
        fi
        if [ -f "/var/run/php/php${PHP_FPM_VERSION}-fpm.sock" ]; then
            PHP_SOCKET="unix:/var/run/php/php${PHP_FPM_VERSION}-fpm.sock"
        else
            PHP_SOCKET="127.0.0.1:9000"
        fi
        PHP_FPM_SERVICE="php${PHP_FPM_VERSION}-fpm"
        ;;
    centos|rhel|fedora|rocky|almalinux)
        if command -v dnf &>/dev/null; then
            dnf install -y epel-release
            dnf install -y nginx php-fpm php-cli php-mbstring php-xml php-curl php-zip php-gd unzip curl wget
        else
            yum install -y epel-release
            yum install -y nginx php-fpm php-cli php-mbstring php-xml php-curl php-zip php-gd unzip curl wget
        fi
        PHP_SOCKET="unix:/var/run/php-fpm/www.sock"
        PHP_FPM_SERVICE="php-fpm"
        ;;
esac

if ! command -v nginx &>/dev/null; then echo -e "${RED}Nginx 安装失败${NC}"; exit 1; fi
if ! command -v php &>/dev/null; then echo -e "${RED}PHP 安装失败${NC}"; exit 1; fi
if ! php -m | grep -q "ctype"; then
    case $OS in
        alpine) apk add --no-cache php-ctype ;;
        ubuntu|debian) apt-get install -y php-ctype 2>/dev/null || apt-get install -y php${PHP_FPM_VERSION}-ctype 2>/dev/null ;;
    esac
fi

echo -e "${GREEN}Nginx 版本: $(nginx -v 2>&1)${NC}"
echo -e "${GREEN}PHP 版本: $(php -v | head -1)${NC}"

# ========== 下载项目 ==========
echo -e "${GREEN}下载 Speedtest-X...${NC}"
mkdir -p "$PROJECT_DIR"
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || exit 1

if command -v git &>/dev/null; then
    git clone https://github.com/MortyFx/speedtest-x.git .
else
    wget -O speedtest-x.zip https://github.com/MortyFx/speedtest-x/archive/refs/heads/master.zip
    unzip -q speedtest-x.zip
    if [ -d speedtest-x-master ]; then
        mv speedtest-x-master/* . 2>/dev/null || true
        mv speedtest-x-master/.[!.]* . 2>/dev/null 2>&1 || true
        rm -rf speedtest-x-master speedtest-x.zip
    fi
fi

cp -a . "$PROJECT_DIR"/
cd /
rm -rf "$TEMP_DIR"

[ ! -f "$PROJECT_DIR/results.json" ] && echo '[]' > "$PROJECT_DIR/results.json"
chmod 666 "$PROJECT_DIR/results.json"
chmod -R 755 "$PROJECT_DIR"
chown -R nginx:nginx "$PROJECT_DIR" 2>/dev/null || true

# ========== 配置 PHP-FPM (alpine) ==========
if [ "$OS" = "alpine" ]; then
    PHP_FPM_CONF=$(find /etc/php* -name "www.conf" 2>/dev/null | head -1)
    if [ -n "$PHP_FPM_CONF" ]; then
        sed -i 's|^listen = 127.0.0.1:9000|listen = /run/php/php-fpm.sock|' "$PHP_FPM_CONF"
        sed -i 's|^listen = 9000|listen = /run/php/php-fpm.sock|' "$PHP_FPM_CONF"
        sed -i 's|^;listen.owner = nobody|listen.owner = nginx|' "$PHP_FPM_CONF"
        sed -i 's|^;listen.group = nobody|listen.group = nginx|' "$PHP_FPM_CONF"
        sed -i 's|^;listen.mode = 0660|listen.mode = 0660|' "$PHP_FPM_CONF"
        mkdir -p /run/php
        chown nginx:nginx /run/php
    fi
fi

# ========== 配置 Nginx ==========
echo -e "${GREEN}配置 Nginx...${NC}"

if [ -d "/etc/nginx/http.d" ]; then
    NGINX_CONF_FILE="/etc/nginx/http.d/speedtest.conf"
elif [ -d "/etc/nginx/conf.d" ]; then
    NGINX_CONF_FILE="/etc/nginx/conf.d/speedtest.conf"
else
    NGINX_CONF_FILE="/etc/nginx/sites-available/speedtest"
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
fi

if [ -z "$PROJECT_NAME" ]; then
    cat > "$NGINX_CONF_FILE" << EOF
server {
    listen $PORT;
    server_name _;

    root $BASE_DIR;
    index index.html index.htm index.php;

    access_log /var/log/nginx/speedtest_access.log;
    error_log /var/log/nginx/speedtest_error.log;

    client_max_body_size 20M;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass $PHP_SOCKET;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
else
    cat > "$NGINX_CONF_FILE" << EOF
server {
    listen $PORT;
    server_name _;

    root $BASE_DIR;
    index index.html index.htm index.php;

    access_log /var/log/nginx/speedtest_access.log;
    error_log /var/log/nginx/speedtest_error.log;

    client_max_body_size 20M;

    location = / {
        return 301 /$PROJECT_NAME/;
    }

    location = /$PROJECT_NAME {
        return 301 /$PROJECT_NAME/;
    }

    location /$PROJECT_NAME/ {
        try_files \$uri \$uri/ /$PROJECT_NAME/index.php?\$args;
    }

    location ~ ^/$PROJECT_NAME/.+\.php\$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass $PHP_SOCKET;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
fi

if [ "$NGINX_CONF_FILE" = "/etc/nginx/sites-available/speedtest" ]; then
    ln -sf "$NGINX_CONF_FILE" /etc/nginx/sites-enabled/speedtest
fi

echo -e "${YELLOW}测试 Nginx 配置...${NC}"
nginx -t 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}Nginx 配置测试失败，尝试 TCP 模式...${NC}"
    sed -i 's|fastcgi_pass unix:/run/php/php-fpm.sock;|fastcgi_pass 127.0.0.1:9000;|' "$NGINX_CONF_FILE"
    nginx -t 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}仍然失败${NC}"; cat "$NGINX_CONF_FILE"; exit 1
    fi
    PHP_SOCKET="127.0.0.1:9000"
fi

# ========== 启动服务 ==========
echo -e "${GREEN}启动服务...${NC}"
if command -v rc-service &>/dev/null; then
    rc-service $PHP_FPM_SERVICE restart 2>/dev/null || {
        rc-service php-fpm restart 2>/dev/null || rc-service php-fpm82 restart 2>/dev/null || rc-service php-fpm83 restart 2>/dev/null
    }
    rc-update add $PHP_FPM_SERVICE default 2>/dev/null || true
    rc-service nginx restart
    rc-update add nginx default 2>/dev/null || true
elif command -v systemctl &>/dev/null; then
    systemctl restart $PHP_FPM_SERVICE 2>/dev/null || true
    systemctl enable $PHP_FPM_SERVICE 2>/dev/null || true
    systemctl restart nginx
    systemctl enable nginx 2>/dev/null || true
else
    service $PHP_FPM_SERVICE restart 2>/dev/null || true
    service nginx restart 2>/dev/null || true
fi

sleep 2
echo -e "${GREEN}检查服务状态...${NC}"
if pgrep -x "nginx" > /dev/null; then echo -e "${GREEN}✓ Nginx 运行中${NC}"
else echo -e "${RED}✗ Nginx 未运行${NC}"; fi
if pgrep -f "php-fpm" > /dev/null; then echo -e "${GREEN}✓ PHP-FPM 运行中${NC}"
else echo -e "${YELLOW}⚠ PHP-FPM 可能未运行${NC}"; fi

# ========== 安装 st 命令 ==========
install_st_command

# ========== 最终信息 ==========
sleep 1
IP=$(curl -s -m 5 4.ipw.cn 2>/dev/null || curl -s -m 5 ipinfo.io/ip 2>/dev/null || curl -s -m 5 ifconfig.me 2>/dev/null || echo "服务器IP")

if [ -z "$PROJECT_NAME" ]; then
    ACCESS_PATH="/"
else
    ACCESS_PATH="/$PROJECT_NAME/"
fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT${ACCESS_PATH}" 2>/dev/null)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "403" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
    STATUS="可访问 (HTTP $HTTP_CODE)"
elif [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
    STATUS="可访问 (HTTP $HTTP_CODE)"
else
    STATUS="请检查服务状态"
fi

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}   Speedtest-X 部署成功！${NC}"
echo -e "${GREEN}================================${NC}"
echo -e "${YELLOW}访问地址:  http://${IP}:${PORT}${ACCESS_PATH}${NC}"
if [ -z "$PROJECT_NAME" ]; then
    echo -e "${YELLOW}部署方式:  根目录${NC}"
else
    echo -e "${YELLOW}部署方式:  子目录 (${PROJECT_NAME})${NC}"
fi
echo -e "${YELLOW}基础目录:  $BASE_DIR${NC}"
echo -e "${YELLOW}项目目录:  $PROJECT_DIR${NC}"
echo -e "${YELLOW}Nginx 配置: $NGINX_CONF_FILE${NC}"
echo -e "${YELLOW}PHP-FPM:    $PHP_SOCKET${NC}"
echo -e "${YELLOW}本地状态:  $STATUS${NC}"
echo ""
echo -e "${BOLD}${GREEN}使用方法:${NC}"
echo -e "  管理菜单: ${BOLD}st${NC}"
echo -e "  卸载:     ${BOLD}$(basename "$0") uninstall${NC}"
echo -e "${GREEN}================================${NC}"

if [ "$STATUS" = "请检查服务状态" ]; then
    echo -e "\n${YELLOW}调试信息:${NC}"
    echo -e "  1. tail -20 /var/log/nginx/error.log"
    echo -e "  2. ps aux | grep php"
    echo -e "  3. curl -v http://127.0.0.1:$PORT${ACCESS_PATH}"
    echo -e "  4. st"
fi

echo -e "\n${GREEN}PHP 已加载扩展:${NC}"
php -m | grep -E "ctype|mbstring|xml|curl|zip|gd|json|openssl" | sed 's/^/  - /'

if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
    echo -e "\n${YELLOW}⚠ 请执行: ufw allow $PORT${NC}"
elif command -v firewall-cmd &>/dev/null && firewall-cmd --state 2>/dev/null | grep -q "running"; then
    echo -e "\n${YELLOW}⚠ 请执行: firewall-cmd --add-port=${PORT}/tcp --permanent && firewall-cmd --reload${NC}"
fi
