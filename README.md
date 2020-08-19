<p align="center"> 本仓库修复了退格显示 '^H' 问题 </p>

<p align="center"> 并增加了验证用户名和密码的脚本文件：checkpsw.sh </p>

**tips1**

> **如果遇到下载失败（拒绝连接）的问题，需要修改一下dns**
```bash
$ sudo vim /etc/resolv.conf
```
将 `nameserver 1.1.1.1` 添加到 nameserver 配置的第一行

---

**tips2**
> **安装默认已经启动**

```bash
# 停止 openvpn
$ service openvpn-server@server stop

# 启动 openvpn
$ service openvpn-server@server start

# 重启 openvpn
$ service openvpn-server@server restart
```

> [checkpsw.sh](http://openvpn.se/files/other/checkpsw.sh) 下载
```bash
$ wget https://git.io/JJNMn -O /etc/openvpn/checkpsw.sh
```

**tips3**
**如果想使用集成（证书+密码 登陆）脚本，请直接运行此命令**
```bash
$ wget https://git.io/JJNAu -O openvpn-install.sh && bash openvpn-install.sh
```

---
---

**New: [wireguard-install](https://github.com/Nyr/wireguard-install) is also available.**

## openvpn-install
OpenVPN [road warrior](http://en.wikipedia.org/wiki/Road_warrior_%28computing%29) installer for Ubuntu, Debian, CentOS and Fedora.

This script will let you set up your own VPN server in no more than a minute, even if you haven't used OpenVPN before. It has been designed to be as unobtrusive and universal as possible.

### Installation
Run the script and follow the assistant:

```bash
$ wget https://git.io/JJNMZ -O openvpn-install.sh && bash openvpn-install.sh
```

Once it ends, you can run it again to add more users, remove some of them or even completely uninstall OpenVPN.

### I want to run my own VPN but don't have a server for that
You can get a VPS from just $1/month at [VirMach](https://billing.virmach.com/aff.php?aff=4109&url=billing.virmach.com/cart.php?gid=18).

### Donations

If you want to show your appreciation, you can donate via [PayPal](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=VBAYDL34Z7J6L) or [cryptocurrency](https://pastebin.com/raw/M2JJpQpC). Thanks!
