import sys
from pathlib import Path


def read_hex_path(prompt_text: str) -> Path:
    while True:
        raw_value = input(prompt_text).strip().strip('"')
        if raw_value:
            path = Path(raw_value)
            if path.exists():
                return path
            print(f"路径不存在: {path}")
        else:
            print("请输入有效路径")



def convert_imem(bin_path: Path, out_path: Path) -> None:
    bin_data = bin_path.read_bytes()
    if len(bin_data) % 4 != 0:
        bin_data += b"\x00" * (4 - len(bin_data) % 4)

    with out_path.open("w", encoding="utf-8") as f:
        for i in range(0, len(bin_data), 4):
            b0 = bin_data[i + 0]
            b1 = bin_data[i + 1]
            b2 = bin_data[i + 2]
            b3 = bin_data[i + 3]
            # RISC-V 小端：byte0=bits[7:0], byte3=bits[31:24]
            inst = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
            f.write(f"{inst:08x}\n")



def convert_dmem(bin_path: Path, out_path: Path,out_path0: Path, out_path1: Path,out_path2: Path,out_path3: Path, total_kb: int) -> None:
    bin_data = bin_path.read_bytes()
    total_bytes = total_kb * 1024
    if total_bytes < 0:
        raise ValueError("dmem总大小不能为负数")

    if len(bin_data) > total_bytes:
        raise ValueError(
            f"dmem.bin大小 {len(bin_data)} 字节超过了目标容量 {total_bytes} 字节"
        )

    if len(bin_data) % 4 != 0:
        bin_data += b"\x00" * (4 - len(bin_data) % 4)

    pad_bytes = total_bytes - len(bin_data)
    if pad_bytes % 4 != 0:
        raise ValueError("dmem总大小必须是4字节对齐")

    bin_data += b"\x00" * pad_bytes

    with (out_path.open("w", encoding="utf-8") as f,
      out_path0.open("w", encoding="utf-8") as f0,
      out_path1.open("w", encoding="utf-8") as f1,
      out_path2.open("w", encoding="utf-8") as f2,
      out_path3.open("w", encoding="utf-8") as f3):
        for i in range(0, len(bin_data), 4):
            b0 = bin_data[i + 0]  # 第一个字节
            f0.write(f"{b0:02x}\n")
            b1 = bin_data[i + 1]  # 第二个字节
            f1.write(f"{b1:02x}\n")
            b2 = bin_data[i + 2]  # 第三个字节
            f2.write(f"{b2:02x}\n")
            b3 = bin_data[i + 3]  # 第四个字节
            f3.write(f"{b3:02x}\n")

            word = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
            f.write(f"{word:08x}\n")



def read_total_kb(prompt_text: str) -> int:
    while True:
        raw_value = input(prompt_text).strip()
        try:
            total_kb = int(raw_value)
            if total_kb > 0:
                return total_kb
            print("请输入大于0的整数")
        except ValueError:
            print("请输入有效的整数")



def main() -> None:
    if len(sys.argv) >= 4:
        # CLI 模式: python bin2mem.py <dmem_kb> <imem_bin> <dmem_bin> [output_dir]
        total_kb = int(sys.argv[1])
        imem_path = Path(sys.argv[2])
        dmem_path = Path(sys.argv[3])
        out_dir = Path(sys.argv[4]) if len(sys.argv) > 4 else Path.cwd()
        out_dir.mkdir(parents=True, exist_ok=True)

        imem_out = out_dir / "imem.mem"
        convert_imem(imem_path, imem_out)
        print(f"imem -> {imem_out}")

        dmem_out = out_dir / "dmem.mem"
        dmem_out0 = out_dir / "dmem0.mem"
        dmem_out1 = out_dir / "dmem1.mem"
        dmem_out2 = out_dir / "dmem2.mem"
        dmem_out3 = out_dir / "dmem3.mem"
        convert_dmem(dmem_path, dmem_out, dmem_out0, dmem_out1, dmem_out2, dmem_out3, total_kb)
        print(f"dmem -> {dmem_out} ({total_kb}KB)")
        return

    # 交互模式（原版）
    current_dir = Path.cwd()
    print(f"当前工作目录: {current_dir}")

    imem_path = read_hex_path("请输入需要转写的 imem.bin 路径: ")
    imem_out = current_dir / "imem.mem"
    convert_imem(imem_path, imem_out)
    print(f"imem 已输出: {imem_out}")

    dmem_path = read_hex_path("请输入需要转写的 dmem.bin 路径: ")
    total_kb = read_total_kb("请输入 dmem 总大小（单位 kb）: ")
    dmem_out = current_dir / "dmem.mem"
    dmem_out0 = current_dir / "dmem0.mem"
    dmem_out1 = current_dir / "dmem1.mem"
    dmem_out2 = current_dir / "dmem2.mem"
    dmem_out3 = current_dir / "dmem3.mem"
    convert_dmem(dmem_path, dmem_out, dmem_out0, dmem_out1, dmem_out2,dmem_out3, total_kb)
    print(f"dmem 已输出: {dmem_out}")


if __name__ == "__main__":
    main()
