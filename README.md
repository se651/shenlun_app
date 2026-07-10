# 练申论 — 公务员考试申论练习 App

一款专为公考申论备考打造的 Flutter 应用，集题库练习、时政积累、AI 批改、素材库于一体。

**免责声明：本软件仅用于免费学习交流，切勿用于牟利。**

## 功能特性

### 📝 题库练习
- **海量真题**：收录历年国考、省考申论真题，支持按题型、关键词搜索
- **模拟考试**：AI 自动组卷，模拟真实考试环境
- **AI 智能批改**：接入 DeepSeek API，五位 AI 老师多维度评分，提供参考范文
- **本地评分**：离线评分引擎，无需网络也可自测

### 📰 时政积累
- **人民日报评论**：精选人民时评文章，支持 AI 要点提炼
- **重要讲话**：收录重要讲话原文及解读
- **重要会议**：跟踪最新会议精神与政策方向
- **组织人事**：关注干部动态与人事调整
- **求是杂志 / 红旗文稿**：理论文章阅读
- **新闻周刊**：每周时政热点汇总

### 📚 素材库
- **政府文档**：历年政府工作报告、重要政策文件
- **人物素材**：典型人物事迹，适用于申论论证
- **党史学习**：党史知识题库与学习材料
- **新兴概念**：最新政策热词与概念解析
- **聚焦重点**：高频考点与重点知识梳理

### 📖 规范词库
- **申论规范词**：1000+ 申论常用规范表达
- **政治词典**：政治术语详细解释
- **习语词典**：经典用语汇编
- **新年贺词**：历年新年贺词汇总

### 🎯 专项练习
- **概括练习**：材料概括能力训练
- **评论练习**：评论性文章写作训练
- **弱项攻克**：针对薄弱题型定向突破
- **错题本**：自动收录错题，反复练习
- **收藏夹**：收藏重点题目与文章

### 🏆 成就系统
- 多级成就徽章：练题达人、政论先锋、环球视野、上岸锦鲤
- 撒花庆祝动画
- 学习数据统计与雷达图

### 🎨 视觉体验
- **三种主题模式**：浅色 / 深色 / 护眼模式
- **字体缩放**：自由调节字号大小
- **每日推送**：AI 生成的每日时政卡片

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter 3.x (Dart SDK ^3.7.2) |
| 本地存储 | SQLite (sqflite) |
| 状态管理 | StatefulWidget + setState |
| HTTP | http |
| HTML 解析 | html |
| 文件操作 | path_provider, file_picker, share_plus |
| PDF | pdf (生成答题卡) |
| WebView | flutter_inappwebview |
| 音频 | audioplayers |
| 动画 | confetti (撒花效果) |
| 平台支持 | Android / iOS / Windows / Linux / macOS / Web |

## 快速开始

### 环境要求

- Flutter SDK >= 3.7.2
- Dart SDK >= 3.7.2
- Android Studio 或 VS Code

### 安装运行

```bash
# 克隆仓库
git clone https://github.com/se651/shenlun_app.git
cd shenlun_app

# 安装依赖
flutter pub get

# 运行应用
flutter run
```

### 构建 APK

```bash
flutter build apk --release
```

APK 输出路径：`build/app/outputs/flutter-apk/app-release.apk`

### AI 批改配置

在应用「我的 → 设置」中填入你的 DeepSeek API Key 即可启用 AI 批改功能。不配置也可使用本地评分引擎。

## 项目结构

```
lib/
├── main.dart                    # 应用入口，主题配置，启动页
├── data/                        # 数据模型
│   ├── important_meetings.dart  # 重要会议数据
│   ├── new_concepts.dart        # 新兴概念数据
│   ├── party_history.dart       # 党史数据
│   ├── person_data.dart         # 人物素材
│   ├── political_dict.dart      # 政治词典
│   ├── xinnian_heci.dart        # 新年贺词
│   └── xiyu_dict.dart           # 习语词典
├── database/
│   └── db_helper.dart           # SQLite 数据库操作
├── scorer/
│   ├── ai_scorer.dart           # AI 评分引擎
│   └── local_scorer.dart        # 本地评分引擎
├── screens/                     # 页面（50+ 页面）
│   ├── home_screen.dart         # 首页
│   ├── question_screen.dart     # 题库
│   ├── news_screen.dart         # 时政
│   ├── words_screen.dart        # 规范词
│   ├── material_library_screen.dart  # 素材库
│   ├── profile_screen.dart      # 我的
│   ├── mock_exam_*.dart         # 模拟考试
│   ├── summary_*.dart           # 概括练习
│   └── ...                      # 更多功能页面
├── services/                    # 业务逻辑层
│   ├── achievement_service.dart # 成就系统
│   ├── daily_push.dart          # 每日推送
│   ├── export_service.dart      # 导出服务
│   ├── mock_exam_generator.dart # 模拟考试生成
│   ├── news_scraper.dart        # 新闻抓取
│   ├── ocr_service.dart         # OCR 识别
│   └── ...                      # 更多服务
└── widgets/                     # 可复用组件
    ├── achievement_overlay.dart # 成就弹窗
    └── shiny_medal.dart         # 闪光勋章
```

## 版本

当前版本：**1.0.0-alpha.58**

## 许可证

本项目仅用于学习交流目的。题库内容版权归原作者所有。

---

> **恰同学少年，风华正茂；书生意气，挥斥方遒。**
