# -*- coding: utf-8 -*-
"""
SeaUI V3.0.0 软著《源程序鉴别材料》生成脚本（02-源程序鉴别材料.txt）

规则（按申请要求）：
- 拼接范围：rov_flutter/lib（.dart）、backend（.py，排除 tests/）、rdkx5（.py，排除 tests/）
- 按模块顺序：① Flutter 客户端 ② PC 后端 ③ RDK X5 板卡网关
- 每页 50 行，页眉 "SeaUI V3.0.0 第 N 页"
- 总页数 > 60 时取前 30 页 + 后 30 页（中间加省略标记）；否则全量
- 全文 UTF-8 输出，统计结果打印到 stdout
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # 仓库根目录
OUT = Path(__file__).resolve().parent / "02-源程序鉴别材料.txt"
LINES_PER_PAGE = 50
FRONT_PAGES = 30
BACK_PAGES = 30
FULL_THRESHOLD = 60

SOFTWARE_HEADER = "SeaUI V3.0.0"


def collect_module_files() -> list:
    """按模块顺序返回 (模块名, 相对路径) 列表。"""

    def under(base_rel):
        base = ROOT / base_rel
        return sorted(p for p in base.rglob("*")
                      if p.is_file()
                      and (p.suffix == ".dart" if base_rel.startswith("rov_flutter") else p.suffix == ".py")
                      and "tests" not in p.relative_to(ROOT).parts
                      and "__pycache__" not in p.relative_to(ROOT).parts
                      and ".mimosa" not in p.relative_to(ROOT).parts)

    files = []

    # 模块①：Flutter 客户端（main → app → core → features/auth → desktop → mobile → shared）
    fl = under("rov_flutter/lib")
    def fl_key(p):
        rel = p.relative_to(ROOT).as_posix()
        if rel.endswith("main.dart"):
            return (0, rel)
        if rel.endswith("rov_flutter/lib/app.dart"):
            return (1, rel)
        if rel.startswith("rov_flutter/lib/core/"):
            return (2, rel)
        if rel.startswith("rov_flutter/lib/features/auth/"):
            return (3, rel)
        if rel.startswith("rov_flutter/lib/features/dashboard/desktop/"):
            return (4, rel)
        if rel.startswith("rov_flutter/lib/features/dashboard/mobile/"):
            return (5, rel)
        if rel.startswith("rov_flutter/lib/features/shared/"):
            return (6, rel)
        return (9, rel)
    files += [("① Flutter 客户端（rov_flutter/lib）", p) for p in sorted(fl, key=fl_key)]

    # 模块②：PC 后端（排除 tests/）
    files += [("② PC 后端（backend，排除 tests）", p) for p in under("backend")]

    # 模块③：RDK X5 板卡网关（排除 tests/）
    files += [("③ RDK X5 板卡网关（rdkx5，排除 tests）", p) for p in under("rdkx5")]

    return files


def main() -> int:
    modules = collect_module_files()
    if not modules:
        print("ERROR: 未收集到任何源码文件", file=sys.stderr)
        return 1

    # 拼接全部内容行（含文件分隔行，均计入页内 50 行）
    lines = []
    seen_modules = []
    total_code_lines = 0
    for module_name, path in modules:
        rel = path.relative_to(ROOT).as_posix()
        if module_name not in seen_modules:
            seen_modules.append(module_name)
        sep = f"/* ==== 文件：{rel} ==== */" if path.suffix == ".dart" \
            else f"# ==== 文件：{rel} ===="
        lines.append(sep)
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            print(f"WARN: 读取失败 {rel}: {exc}", file=sys.stderr)
            continue
        file_lines = text.splitlines()
        total_code_lines += len(file_lines)
        lines.extend(file_lines)
        if not text.endswith("\n"):
            pass  # splitlines 已按行拆分，无需补行

    total_pages = max(1, (len(lines) + LINES_PER_PAGE - 1) // LINES_PER_PAGE)

    def render_pages(page_numbers):
        out = []
        for n in page_numbers:
            chunk = lines[(n - 1) * LINES_PER_PAGE: n * LINES_PER_PAGE]
            out.append(f"{SOFTWARE_HEADER} 第 {n} 页")
            out.extend(chunk)
            out.append("")  # 页尾空行分隔
        return out

    if total_pages <= FULL_THRESHOLD:
        included = list(range(1, total_pages + 1))
        body = render_pages(included)
        mode = "全量（不足 60 页）"
    else:
        front = list(range(1, FRONT_PAGES + 1))
        back = list(range(total_pages - BACK_PAGES + 1, total_pages + 1))
        body = render_pages(front)
        body.append(f"……（中间内容省略：第 {FRONT_PAGES + 1} 页至第 {total_pages - BACK_PAGES} 页，"
                    f"共 {total_pages - BACK_PAGES - FRONT_PAGES} 页略）……")
        body.append("")
        body += render_pages(back)
        included = front + back
        mode = f"前 {FRONT_PAGES} 页 + 后 {BACK_PAGES} 页"

    header = [
        f"{SOFTWARE_HEADER} 源程序鉴别材料",
        f"（前 30 页 + 后 30 页：每页 50 行，页码见页眉；中间省略处已标注）"
        if total_pages > FULL_THRESHOLD else "（全量：每页 50 行，页码见页眉）",
        f"模块顺序：{'；'.join(seen_modules)}",
        "",
    ]

    OUT.write_text("\n".join(header + body) + "\n", encoding="utf-8")

    print(f"模块文件数: {len(modules)}")
    print(f"源码总行数(不含分隔行): {total_code_lines}")
    print(f"拼接总行数(含分隔行): {len(lines)}")
    print(f"总页数: {total_pages}（每页 {LINES_PER_PAGE} 行）")
    print(f"提交方式: {mode}")
    print(f"提交页码: 第 {included[0]}-{included[FRONT_PAGES - 1]} 页 + "
          f"第 {included[FRONT_PAGES]}-{included[-1]} 页" if total_pages > FULL_THRESHOLD
          else f"提交页码: 第 1-{total_pages} 页")
    print(f"输出文件: {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
