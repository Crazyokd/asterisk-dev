# 初始化ast镜像

1. 使用ubuntu22.04镜像

```
root@15490835f457:/work# cat /etc/issue
Ubuntu 22.04.3 LTS \n \l
```

2. 下载asterisk18并解压

```
wget https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-18-current.tar.gz
tar zxvf asterisk-18-current.tar.gz
```

3. 使用自带脚本安装依赖：

```
/work/asterisk-18.20.2/contrib/scripts# ./install_prereq test
/work/asterisk-18.20.2/contrib/scripts# ./install_prereq install
```

4. 编译项目

```
root@15490835f457:/work/asterisk-18.20.2# ./configure
root@15490835f457:/work/asterisk-18.20.2# make menuselect # optional: remove chan_sip module
root@15490835f457:/work/asterisk-18.20.2# make && make install
```

5. 安装服务脚本

```shell
make config
## systemctl status asterisk
## /etc/init.d/asterisk start
## /etc/init.d/asterisk status
make install-logrotate
```

5. 使用上述镜像

```
docker run --rm --network=host --name ast -it ast bash
# 内部网络使用代理
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
export all_proxy=http://127.0.0.1:7890
```

# 运行
```shell
docker-compose up -d
```
