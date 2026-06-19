# Changelog

所有重要更改都将记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)。

## [1.1.5] - 2026-06-19

### 优化
- 增强 WFDialog 组件，新增 confirm() 和 singleChoice() 静态方法，统一确认和选择弹窗样式
- 迁移字符编辑器中的 AlertDialog 为统一 WFDialog，保持一致的圆角和内边距风格
- 迁移画笔粗细选择弹窗为 WFDialog，添加主题色 Slider
- 迁移首页项目选择弹窗为 WFDialog.singleChoice，统一列表项样式
- 新增 WFAnimations.fadeRoute() 淡入路由动画，用于对话框和页面过渡
- 统一所有确认对话框的按钮文案颜色，使用 WFColors 设计常量

## [1.1.4] - 2026-06-19

### 优化
- 优化图片加载缓存策略，所有 Image.memory/Image.file 组件统一使用 cacheWidth/cacheHeight
- 提取 image_processor.dart 和 recognition_service.dart 中重复的 Otsu 阈值算法为公共方法
- 统一 app_config_service.dart 中所有 SharedPreferences 操作的错误处理模式
- 添加用户友好的错误提示和调试日志

## [1.1.3] - 2026-06-19

### 优化
- 拆分 home_screen.dart (717行) 为 4 个独立组件（主文件 ≤200 行）
- 拆分 font_preview_screen.dart (711行) 为 4 个独立组件（主文件 ≤250 行）
- 提取 WelcomeHeader、RecentProjectsSection、SecondaryEntryCard 等为独立 StatelessWidget
- 提取 PreviewInputArea、PreviewContent、PreviewToolbar、PreviewEmptyState 为独立组件
- 提取业务逻辑为 HomeActions 辅助类，提升可测试性
- 子组件通过回调函数通信，避免循环依赖

## [1.1.2] - 2026-06-19

### 优化
- 拆分 preview_screen.dart 为 7 个独立组件（主文件 ≤300 行）
- 拆分 auto_generate_screen.dart 为 8 个独立组件（主文件 ≤300 行）
- 拆分 capture_screen.dart 为 8 个独立组件（主文件 ≤300 行）
- 提取业务逻辑为独立 helper 文件，提升可测试性

## [1.1.1] - 2026-06-19

### 优化
- 代码质量优化，修复潜在的late变量初始化问题
- 优化大文件结构，提升代码可维护性
- 优化内存管理，减少不必要的资源占用

## [1.1.0] - 2026-06-19

### 优化
- 全应用 7 个页面统一导航栏样式
- 提取硬编码颜色为统一设计常量
- 优化 7 处图片加载缓存策略，降低内存占用
- 增强错误处理与用户反馈机制

### 修复
- 修复字符编辑保存失败时无提示的问题
- 修复临时文件清理失败静默吞错
- 修复备份清理失败无日志记录

## [1.0.0] - 2026-06-19

### 优化
- 启动链路重构，移除冗余依赖初始化
- 全面梳理系统交互请求，移除非必要中断式弹窗
- 收紧数据采集范围，遵循数据最小化原则
- 启用 Release 级别混淆与压缩

### 修复
- 修复首页路由渲染逻辑，解决永久转圈问题
- 修复冷启动阶段潜在的崩溃隐患
- 修复极端网络环境下的容错问题

### 工程
- 版本号重置，建立干净基线
- 修复 CI/CD 流水线
- 移除调试符号与冗余日志
