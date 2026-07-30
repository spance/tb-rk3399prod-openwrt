# 启动内存布局

U-Boot `dump_bidram`/启动输出给出的可用 DRAM bank：

```text
0x00200000 - 0x08400000
0x0a200000 - 0xf8000000
```

中间的 `0x08400000-0x0a200000` 是当前 `trust.img` 中 BL32/OP-TEE 使用的安全内存空洞。约 30 MiB FIT 若加载到 `0x08000000`，范围会进入该空洞，U-Boot 在解析 FIT/libfdt 时可能触发 `Synchronous Abort`。可信固件组成和启动链边界见 [启动链设计](BOOT-CHAIN.md)。

统一约定：

```text
FIT load address:    0x10000000
Linux load address:  0x00280000
Linux entry:         0x00280000
FDT work address:    0x08300000
U-Boot bootm limit:  0x08000000 (128 MiB)
UART earlycon:       0xff1a0000
```

`0x00280000 + 128 MiB = 0x08280000`，因此允许的最大内核仍完整位于第一个
DRAM bank，并在 `fdt_addr_r=0x08300000` 前保留 512 KiB；FDT 本身则必须结束于
`0x08400000` 前。构建脚本会检查正常 FIT 和 initramfs FIT 的 load address、
内核数据长度及结束地址，不能仅靠扩大 `CONFIG_SYS_BOOTM_LEN` 掩盖内存重叠。

升级后仍应按实际 FIT 大小重新检查其在 `0x10000000` 的载入范围，确保 FIT
源数据不与目标内核或可信内存重叠。
