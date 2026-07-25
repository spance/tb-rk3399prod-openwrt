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
Linux load address:  0x03200000
Linux entry:         0x03200000
UART earlycon:       0xff1a0000
```

升级后应按实际 FIT 大小重新检查加载范围，确保其不进入安全内存，也不与内核目标地址重叠。
