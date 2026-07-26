# 网络性能与加速策略

## 已确认基线

板载 GMAC 当前显示为 `eth0`，使用 stmmac/DWMAC1000 和 RTL8211E PHY。Linux 6.12.94 下已完成两个方向各 1800 秒、4 条 TCP 流的千兆压力测试：

| 方向 | 平均吞吐 | 数据量 | 结果 |
|---|---:|---:|---|
| TB-RK3399ProD → 对端 | 941 Mbit/s | 197 GiB | 180 次 TCP 重传；GMAC/PHY 错误计数为 0 |
| 对端 → TB-RK3399ProD | 941 Mbit/s | 197 GiB | GMAC/PHY 错误计数为 0 |

这已经达到普通千兆以太网扣除帧和 TCP/IP 开销后的线速范围。测试前后没有 CRC、alignment、carrier、collision、DMA、FIFO、watchdog 或 fatal bus error 增量。

## GMAC IRQ 放置

RK3399 的 CPU0–CPU3 是 Cortex-A53，CPU4–CPU5 是 Cortex-A72。板载 GMAC 当前只有一组 RX/TX queue，实机 IRQ 名称为 `eth0`；IRQ 编号可能随内核和设备 probe 顺序改变，不能固定写成 41。

`rootfs/etc/init.d/tb-net-tuning` 先通过固定平台设备 `fe300000.ethernet` 找到板载 GMAC 的当前接口名，再从 `/proc/interrupts` 动态解析它的全部 IRQ，并将 `smp_affinity_list` 设为 CPU4，即第一颗 Cortex-A72。它不依赖未来可能变化的 `eth0/eth1` 编号。运行时 A/B 验证表明硬中断计数从 CPU0 转移到 CPU4；随后 30 秒、4 流复测为 942/941 Mbit/s、0 重传，错误计数仍为 0。

GMAC IRQ 只有在 netifd 打开网卡后才会出现，因此不能在网络服务之前只执行一次。`rootfs/etc/hotplug.d/iface/90-tb-net-tuning` 在逻辑接口 `lan` 的 `ifup` 事件后调用上述服务，使正常开机和以后重启网络都能恢复 affinity；服务自身延后到 S99，再提供一次幂等兜底。二者最终都调用同一段按平台设备查找 IRQ 的逻辑，不维护重复规则。

这只规定 GMAC 硬中断落点，不强制固定应用进程，也不启用 RPS/RFS。协议栈、NAPI 和发送线程仍可能在其他 CPU 上产生软中断负载。对于单队列千兆 GMAC，额外跨核 RPS 容易增加 cache miss，目前没有证据表明它能改善吞吐，因此不作为默认项。

检查命令：

```sh
grep -w eth0 /proc/interrupts
irq="$(awk '$NF == "eth0" { gsub(":", "", $1); print $1; exit }' /proc/interrupts)"
cat "/proc/irq/$irq/smp_affinity_list"
logread | grep tb-net-tuning
```

## 软件 flow offload

首次启动脚本 `rootfs/etc/uci-defaults/99-tb-network-offload` 设置：

```text
firewall.@defaults[0].flow_offloading='1'
firewall.@defaults[0].flow_offloading_hw='0'
```

fw4 会为已建立的 TCP/UDP 转发连接生成 nftables flowtable，使后续数据包绕过一部分常规 netfilter 路径。这只加速经过路由器转发的流量；连接到 OpenWrt 本机的 SSH、iperf3 或文件传输不会受益。当前单网口配置只能验证 flowtable 能正确生成，必须在 PCIe 第二网卡形成 LAN/WAN 后进行 NAT/路由 A/B 测试，才能量化收益。

板载 DWMAC1000 报告 `hw-tc-offload: off [fixed]`，因此硬件 flow offload 保持关闭。若启用 SQM/CAKE、需要逐包统计、复杂 nftables 策略或流量镜像，应重新验证规则语义；必要时执行：

```sh
uci set firewall.@defaults[0].flow_offloading='0'
uci commit firewall
/etc/init.d/firewall restart
```

## AES 与 Rockchip Crypto

六个 CPU 均报告 ARMv8 `aes`、`pmull`、`sha1`、`sha2` 和 `crc32` 指令特性；当前内核已经注册 `aes-ce`、`gcm-aes-ce`、`xts-aes-ce` 等实现。现代 TLS 通常由用户态密码库直接使用 ARMv8 指令；常见的 AES-GCM IPsec 则可以使用内核 AES-CE/GHASH-CE。

OpenSSL 3.5.7 使用 16 KiB 数据块、固定单个 Cortex-A72 进行的实机基准如下；纯软件对照通过 `OPENSSL_armcap=0` 禁用 ARM capability，测试工具仅在 RAM 中临时运行：

| 算法 | ARMv8 AES-CE | 纯软件 | 加速倍数 |
|---|---:|---:|---:|
| AES-128-CBC | 1.347 GB/s | 112 MB/s | 12.0× |
| AES-256-CBC | 1.017 GB/s | 83 MB/s | 12.2× |
| AES-128-GCM | 1.395 GB/s | 61.9 MB/s | 22.5× |
| AES-256-GCM | 1.195 GB/s | 51.8 MB/s | 23.1× |

两个 Cortex-A72 并行时，AES-128-GCM 与 AES-256-GCM 合计分别达到约 2.794 GB/s 和 2.408 GB/s。该数据证明 ARMv8 密码指令路径生效，但不等同于含协议、封装、网络和防火墙开销的 VPN 端到端吞吐。

RK3399 的两个 Crypto v1 引擎确实存在，但 Linux 6.12 的 `rk3288_crypto` 驱动仅注册 AES ECB/CBC、DES/3DES、MD5、SHA-1 和 SHA-256，没有 GCM、CTR 或 XTS。它与 AES-CE 的 ECB/CBC priority 同为 300，并且 DMA 对长度、对齐和 scatterlist 有回退条件。Linux 6.12 的 RK3399 SoC DTS 没有正式启用这两个节点；直接加入节点还要承担尚未进入主线 DTS 的维护和回归成本。

因此生产 profile 保留 ARMv8 AES-CE，不默认启用 Rockchip Crypto。以后只有在明确出现内核 CBC/SHA 吞吐瓶颈时才做独立实验镜像：加入两个 Crypto 节点和驱动、确认 DMA/IRQ/运行时 PM 无错误，然后用相同算法、块大小和并发度与 AES-CE 对照。它不能加速普通明文 IP 转发，也不能替代软件 flow offload。

## PCIe 第二网卡

安装 PCIe 网卡后，应先按真实驱动和硬件能力检查：

```sh
ethtool -l eth1
ethtool -x eth1
grep -E 'eth1|PCI-MSI' /proc/interrupts
ethtool -k eth1
ethtool -S eth1
```

若网卡提供多组 RX/TX queue 和 MSI-X，再把各 queue IRQ 分散到 CPU4、CPU5，并用 RSS indirection table 保持流级一致性。不要把板载单队列 GMAC 的绑核规则机械套用到 PCIe 网卡。最终验收应包括普通路由、NAT、软件 flow offload 开/关、双向并发、MTU 变化、长时间错误计数和温控。
