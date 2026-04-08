# Gost SOCKS5 一键安装脚本说明

这个脚本用于在常见 Linux 系统上快速安装 [Gost](https://github.com/go-gost/gost)，并创建一个带用户名密码认证的 SOCKS5 代理，同时配置开机自启。

支持系统：

- Alpine Linux：使用 OpenRC
- Debian / Ubuntu：使用 systemd
- CentOS / Rocky / AlmaLinux / RHEL / Fedora：使用 systemd

支持架构：

- amd64 / x86_64
- arm64 / aarch64
- armv7
- armv6
- 386

---

## 1. 功能特性

- 自动识别系统类型
- 自动识别 CPU 架构
- 自动下载安装 Gost
- 自动创建 SOCKS5 用户名、密码、端口配置
- 自动生成开机自启服务
- Alpine 使用 OpenRC
- Debian / Ubuntu / CentOS 等使用 systemd
- 自动输出本机测试命令

---

## 2. 文件说明

脚本文件：

```bash
install_gost_socks5.sh
```

推荐和本说明文件一起放到同一个仓库中。

---

## 3. 使用前提

请使用 `root` 用户执行，或者先切换到 root：

```bash
sudo -i
```

如果系统没有 `curl` / `wget` / `tar`，脚本会自动安装。

---

## 4. 快速使用

### 方式一：下载后执行

```bash
chmod +x install_gost_socks5.sh
./install_gost_socks5.sh
```

或者：

```bash
bash install_gost_socks5.sh
```

运行后会提示输入：

- SOCKS5 用户名
- SOCKS5 密码
- SOCKS5 端口

默认值：

- 用户名：`global`
- 密码：`ChangeMe123456`
- 端口：`22026`

---

## 5. GitHub 远程一键执行

如果你把脚本传到 GitHub，可以直接这样执行：

```bash
curl -fsSL https://raw.githubusercontent.com/echo00023/gost_socks_install/refs/heads/main/install_gost_socks5.sh | sh
```

或者：

```bash
wget -qO- https://raw.githubusercontent.com/echo00023/gost_socks_install/refs/heads/main/install_gost_socks5.sh | sh
```

> 注意：远程执行前请先确认脚本内容可信。

---

## 6. 非交互使用

脚本支持通过环境变量预设参数，适合自动化部署。

### 示例

```bash
SOCKS_USER=myuser \
SOCKS_PASS='MyStrongPass@123' \
SOCKS_PORT=22026 \
GOST_VERSION=3.2.6 \
sh install_gost_socks5.sh
```

说明：

- `SOCKS_USER`：SOCKS5 用户名
- `SOCKS_PASS`：SOCKS5 密码
- `SOCKS_PORT`：监听端口
- `GOST_VERSION`：Gost 版本，默认 `3.2.6`

如果这些变量已设置，脚本不会再交互询问。

---

## 7. 安装后验证

### 查看 Gost 版本

```bash
gost -V
```

### 查看端口监听

```bash
ss -lntp | grep 22026
```

把 `22026` 替换成你自己的端口。

### 本机测试代理

```bash
curl --socks5 用户名:密码@127.0.0.1:端口 http://ifconfig.me
```

示例：

```bash
curl --socks5 global:ChangeMe123456@127.0.0.1:22026 http://ifconfig.me
```

如果返回的是服务器公网 IP，说明 SOCKS5 工作正常。

---

## 8. 服务管理

### Debian / Ubuntu / CentOS / Rocky / AlmaLinux / RHEL / Fedora

查看状态：

```bash
systemctl status gost
```

重启服务：

```bash
systemctl restart gost
```

停止服务：

```bash
systemctl stop gost
```

设置开机自启：

```bash
systemctl enable gost
```

查看服务文件：

```bash
cat /etc/systemd/system/gost.service
```

环境变量文件：

```bash
cat /etc/gost/gost.env
```

---

### Alpine Linux

查看状态：

```bash
rc-service gost status
```

重启服务：

```bash
rc-service gost restart
```

停止服务：

```bash
rc-service gost stop
```

加入开机启动：

```bash
rc-update add gost default
```

查看服务脚本：

```bash
cat /etc/init.d/gost
```

查看日志：

```bash
cat /var/log/gost.log
```

---

## 9. 配置位置

### Gost 主程序

```bash
/usr/local/bin/gost
```

### systemd 服务文件

```bash
/etc/systemd/system/gost.service
```

### systemd 环境变量文件

```bash
/etc/gost/gost.env
```

### OpenRC 服务文件

```bash
/etc/init.d/gost
```

### Alpine 日志文件

```bash
/var/log/gost.log
```

---

## 10. 更换账号、密码、端口

最简单的方法是重新运行脚本，输入新的参数。

如果你要手动修改：

### systemd 系统

编辑：

```bash
vi /etc/gost/gost.env
```

修改后重载并重启：

```bash
systemctl daemon-reload
systemctl restart gost
```

### Alpine / OpenRC

编辑：

```bash
vi /etc/init.d/gost
```

修改 `command_args` 后重启：

```bash
rc-service gost restart
```

---

## 11. 常见问题

### 1）端口被占用

报错类似：

```bash
bind: address already in use
```

排查：

```bash
ss -lntp | grep 你的端口
```

处理方式：

- 关闭占用该端口的程序
- 或者换一个新端口重新安装/配置

---

### 2）OpenRC 服务启动后显示 crashed

先前台运行检查：

```bash
/usr/local/bin/gost -L 'socks5://用户名:密码@:端口'
```

如果前台能正常监听，通常是服务脚本格式或日志设置问题。

再检查：

```bash
cat /etc/init.d/gost
cat /var/log/gost.log
```

---

### 3）systemd 启动失败

查看日志：

```bash
journalctl -u gost -n 50 --no-pager
```

---

### 4）远程无法连接，但本机测试正常

这通常不是脚本问题，而是防火墙或云安全组未放行端口。

请检查：

- 云服务器安全组
- 服务器防火墙
- 运营商网络限制

需要放行：

- 协议：TCP
- 端口：你设置的 SOCKS5 端口

---

### 5）密码里有特殊字符能不能用

可以。脚本会对用户名和密码自动做 URL 编码，避免因为 `@`、`:`、`#`、`&` 等字符导致 Gost 启动失败。

---

## 12. 卸载方法

### systemd 系统

```bash
systemctl stop gost
systemctl disable gost
rm -f /etc/systemd/system/gost.service
rm -rf /etc/gost
systemctl daemon-reload
rm -f /usr/local/bin/gost
```

### Alpine / OpenRC

```bash
rc-service gost stop
rc-update del gost default
rm -f /etc/init.d/gost
rm -f /var/log/gost.log
rm -f /usr/local/bin/gost
```

---

## 13. 推荐测试命令

假设配置如下：

- 用户名：`global`
- 密码：`ChangeMe123456`
- 端口：`22026`

本机测试：

```bash
curl --socks5 global:ChangeMe123456@127.0.0.1:22026 http://ifconfig.me
```

远程客户端配置：

- 类型：SOCKS5
- 地址：你的服务器公网 IP
- 端口：22026
- 用户名：global
- 密码：ChangeMe123456

---

## 14. 安全建议

- 不要使用过于简单的密码
- 尽量使用 16 位以上随机密码
- 不要使用常见端口，避免被扫描
- 建议在云平台安全组中仅允许自己的 IP 访问
- 定期更换密码

---

## 15. 示例：最常用的一键部署方式

交互式：

```bash
bash install_gost_socks5.sh
```

非交互式：

```bash
SOCKS_USER=global SOCKS_PASS='MyPass@2026' SOCKS_PORT=22026 bash install_gost_socks5.sh
```

GitHub 远程执行：

```bash
curl -fsSL https://raw.githubusercontent.com/echo00023/gost_socks_install/refs/heads/main/install_gost_socks5.sh | \
SOCKS_USER=global SOCKS_PASS='MyPass@2026' SOCKS_PORT=22026 sh
```

---

## 16. 说明

这个脚本当前默认安装 Gost `v3.2.6`。如果后续你更新了仓库，建议同步更新：

- 脚本中的默认版本
- 本说明文档中的命令示例

