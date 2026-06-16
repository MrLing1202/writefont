"""
WriteFont CLI入口

支持的命令:
  writefont run        - 一键完成从图片到字体
  writefont preprocess - 图像预处理
  writefont ocr        - OCR识别
  writefont style      - 风格提取
  writefont generate   - 字体生成
"""

import argparse
import sys
from pathlib import Path


def main() -> None:
    """CLI主入口函数"""
    parser = argparse.ArgumentParser(
        prog="writefont",
        description="手迹造字 - 从手写样本生成完整字体库",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  writefont run --input photo.jpg --output my_font.ttf
  writefont preprocess --input photo.jpg --output processed/
  writefont ocr --input processed/ --output recognized.json
  writefont style --input recognized.json --output style_vector.pt
  writefont generate --style style_vector.pt --output font.ttf
        """,
    )

    subparsers = parser.add_subparsers(dest="command", help="可用命令")

    # run 命令 - 一键完成
    run_parser = subparsers.add_parser("run", help="一键完成：从图片到字体")
    run_parser.add_argument("--input", "-i", required=True, help="输入图片路径")
    run_parser.add_argument("--output", "-o", required=True, help="输出字体路径")
    run_parser.add_argument("--charset", default="gb2312", help="字符集 (默认: gb2312)")
    run_parser.add_argument("--config", default=None, help="配置文件路径")

    # preprocess 命令
    pre_parser = subparsers.add_parser("preprocess", help="图像预处理")
    pre_parser.add_argument("--input", "-i", required=True, help="输入图片路径")
    pre_parser.add_argument("--output", "-o", required=True, help="输出目录")

    # ocr 命令
    ocr_parser = subparsers.add_parser("ocr", help="OCR识别")
    ocr_parser.add_argument("--input", "-i", required=True, help="输入图片目录")
    ocr_parser.add_argument("--output", "-o", required=True, help="输出JSON路径")

    # style 命令
    style_parser = subparsers.add_parser("style", help="风格提取")
    style_parser.add_argument("--input", "-i", required=True, help="输入JSON路径")
    style_parser.add_argument("--output", "-o", required=True, help="输出风格向量路径")

    # generate 命令
    gen_parser = subparsers.add_parser("generate", help="字体生成")
    gen_parser.add_argument("--style", required=True, help="风格向量路径")
    gen_parser.add_argument("--output", "-o", required=True, help="输出目录")
    gen_parser.add_argument("--charset", default="common_3500", help="字符集 (默认: common_3500)")

    args = parser.parse_args()

    if args.command is None:
        parser.print_help()
        sys.exit(0)

    # 延迟导入，避免CLI帮助信息加载过慢
    from writefont_core.pipeline import WriteFontPipeline

    pipeline = WriteFontPipeline(
        config_path=args.config if hasattr(args, "config") else None
    )

    if args.command == "run":
        result = pipeline.run(
            input_path=args.input,
            output_path=args.output,
            charset=args.charset,
        )
        print(f"✅ 字体已生成: {result.font_path}")
        print(f"   字符数: {result.char_count}")
        print(f"   格式: {', '.join(result.formats)}")

    elif args.command == "preprocess":
        result = pipeline.preprocess(args.input, args.output)
        print(f"✅ 预处理完成: {result['output_dir']}")
        print(f"   识别到 {result['char_count']} 个字符图片")

    elif args.command == "ocr":
        result = pipeline.recognize(args.input, args.output)
        print(f"✅ OCR完成: {result['output_path']}")
        print(f"   识别 {result['total']} 个字符，平均置信度 {result['avg_confidence']:.2%}")

    elif args.command == "style":
        result = pipeline.extract_style(args.input, args.output)
        print(f"✅ 风格提取完成: {result['output_path']}")
        print(f"   特征维度: {result['feature_dim']}")

    elif args.command == "generate":
        result = pipeline.generate_font(args.style, args.output, charset=args.charset)
        print(f"✅ 字体生成完成: {result['font_path']}")
        print(f"   字符数: {result['char_count']}")


if __name__ == "__main__":
    main()
