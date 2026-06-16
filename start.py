#!/usr/bin/env python3
"""
手迹造字 WriteFont — 一键启动脚本
双击运行即可启动，自动检测并安装依赖

用法:
  python start.py              # 启动 Gradio Web UI（默认）
  python start.py --api        # 启动 REST API 服务器
  python start.py --api --port 9000  # 指定端口启动 API
"""
import argparse
import subprocess
import sys
import os
import shutil


def check_python() -> None:
    """检查 Python 版本。"""
    if sys.version_info < (3, 9):
        print(f"❌ 需要 Python 3.9+，当前版本 {sys.version}")
        print("   请访问 https://www.python.org/downloads/ 下载最新版本")
        sys.exit(1)
    print(f"✅ Python {sys.version.split()[0]}")


def check_tesseract() -> bool:
    """检查 Tesseract OCR 是否安装。"""
    if shutil.which("tesseract"):
        print("✅ Tesseract OCR 已安装")
        return True

    print("⚠️  Tesseract OCR 未安装，正在尝试自动安装...")
    system = sys.platform

    try:
        if system == "darwin":  # macOS
            subprocess.run(["brew", "install", "tesseract"], check=True)
        elif system == "linux":
            subprocess.run(["sudo", "apt", "install", "-y", "tesseract-ocr"], check=True)
        elif system == "win32":
            print("   请手动下载安装: https://github.com/UB-Mannheim/tesseract/wiki")
            print("   安装后将路径添加到 PATH 环境变量")
            return False
        print("✅ Tesseract OCR 安装完成")
        return True
    except Exception as e:
        print(f"   自动安装失败: {e}")
        print("   请手动安装 Tesseract OCR: https://tesseract-ocr.github.io/tessdoc/Installation.html")
        return False


def install_deps() -> None:
    """安装 Python 依赖。"""
    project_dir = os.path.dirname(os.path.abspath(__file__))
    req_file = os.path.join(project_dir, "requirements.txt")
    if not os.path.exists(req_file):
        print("⚠️  requirements.txt 不存在，跳过依赖安装")
        return

    print("📦 正在安装 Python 依赖...")
    try:
        subprocess.run(
            [sys.executable, "-m", "pip", "install", "-r", req_file, "--quiet"],
            check=True,
        )
        print("✅ 依赖安装完成")
    except subprocess.CalledProcessError:
        print("⚠️  部分依赖安装失败，尝试继续启动...")

    # 以开发模式安装本项目（确保 import writefont 可用）
    setup_file = os.path.join(project_dir, "setup.py")
    pyproject_file = os.path.join(project_dir, "pyproject.toml")
    if os.path.exists(setup_file) or os.path.exists(pyproject_file):
        try:
            subprocess.run(
                [sys.executable, "-m", "pip", "install", "-e", project_dir, "--quiet"],
                check=True,
            )
            print("✅ 项目已安装到 Python 环境")
        except subprocess.CalledProcessError:
            # 尝试手动添加 src 到路径
            src_dir = os.path.join(project_dir, "src")
            if src_dir not in sys.path:
                sys.path.insert(0, src_dir)
            print("⚠️  项目安装失败，已将 src/ 添加到 Python 路径")


def start_app(api_mode: bool = False, host: str = "0.0.0.0", port: int = 8000) -> None:
    """启动应用。

    Args:
        api_mode: 是否启动 REST API 模式（否则启动 Gradio Web UI）
        host: API 模式下的监听地址
        port: API 模式下的监听端口
    """
    project_dir = os.path.dirname(os.path.abspath(__file__))

    if api_mode:
        # REST API 模式
        print("\n" + "=" * 50)
        print("  🖌️  手迹造字 WriteFont API")
        print(f"  正在启动... 监听 http://{host}:{port}")
        print(f"  API 文档: http://{host}:{port}/docs")
        print("=" * 50 + "\n")

        try:
            # 确保 src 目录在 Python 路径中
            src_dir = os.path.join(project_dir, "src")
            if src_dir not in sys.path:
                sys.path.insert(0, src_dir)

            from writefont.api_server import start_server
            start_server(host=host, port=port)
        except ImportError as e:
            print(f"\n❌ 缺少依赖: {e}")
            print("   请安装 FastAPI 和 Uvicorn:")
            print(f"   {sys.executable} -m pip install fastapi uvicorn")
            sys.exit(1)
        except KeyboardInterrupt:
            print("\n👋 已退出，感谢使用！")
        except Exception as e:
            print(f"\n❌ API 服务器启动失败: {e}")
            sys.exit(1)
    else:
        # Gradio Web UI 模式
        app_path = os.path.join(project_dir, "src", "writefont", "frontend", "app.py")

        if not os.path.exists(app_path):
            print(f"❌ 找不到应用入口: {app_path}")
            sys.exit(1)

        print("\n" + "=" * 50)
        print("  🖌️  手迹造字 WriteFont")
        print("  正在启动... 首次启动可能需要 30 秒")
        print("  启动后浏览器会自动打开 http://localhost:7860")
        print("=" * 50 + "\n")

        try:
            subprocess.run([sys.executable, app_path], check=True)
        except KeyboardInterrupt:
            print("\n👋 已退出，感谢使用！")
        except Exception as e:
            print(f"\n❌ 启动失败: {e}")
            print("   请检查是否正确安装了所有依赖:")
            print(f"   {sys.executable} -m pip install -r requirements.txt")


def parse_args() -> argparse.Namespace:
    """解析命令行参数。"""
    parser = argparse.ArgumentParser(
        description="手迹造字 WriteFont — 一键启动脚本",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  python start.py                    # 启动 Gradio Web UI
  python start.py --api              # 启动 REST API 服务器
  python start.py --api --port 9000  # 指定端口启动 API
  python start.py --api --host 127.0.0.1  # 仅监听本地
        """,
    )
    parser.add_argument(
        "--api",
        action="store_true",
        help="启动 REST API 服务器模式（默认启动 Gradio Web UI）",
    )
    parser.add_argument(
        "--host",
        default="0.0.0.0",
        help="API 服务器监听地址（默认: 0.0.0.0）",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8000,
        help="API 服务器监听端口（默认: 8000）",
    )
    return parser.parse_args()


def main() -> None:
    """主入口函数。"""
    args = parse_args()

    print("🔍 环境检查...\n")
    check_python()
    check_tesseract()
    install_deps()
    start_app(api_mode=args.api, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
