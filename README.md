# Rebased 中文语言包配置工具

双击 `配置中文.bat` 即可运行。自动发现 Rebased 和 IDEA 中文语言包，安装并修补兼容性，配置默认中文。

## 目录结构

```
├── 配置中文.bat                 双击运行
├── README.md                    本文件
└── src/
    ├── Update-RebasedChinese.ps1   主脚本
    └── modules/
        ├── discovery.ps1           路径发现
        ├── plugin.ps1              插件复制与修补
        ├── config.ps1              配置文件修改
        └── pack.ps1                ZIP 打包
```

## 使用方法

双击 `配置中文.bat`，按提示操作：

```
=======================================================
  Rebased 中文语言包配置工具
=======================================================

如何定位 Rebased 和语言包？

  [1] 自动搜索
  [2] 手动指定路径
  [0] 退出
```

### 第 1 步：选择发现方式

- `[1] 自动搜索` — 扫描常用目录，列出找到的 Rebased 和语言包
- `[2] 手动指定路径` — 直接输入 Rebased 和语言包的路径
- `[0] 退出`

### 第 2 步：选择具体实例

如果选了自动搜索，会列出所有找到的 Rebased 安装：

```
找到 2 个 Rebased:

  [1] C:\迅雷下载\rebased.win(1)
      版本: 1.1.17  build 262.10968.SNAPSHOT
  [2] C:\home\app\devApp\rebased.win
      版本: 1.1.16  build 262.10315.SNAPSHOT
  [0] 退出

  选择:
```

然后列出找到的中文语言包：

```
找到 3 个中文语言包:

  [1] C:\...\IntelliJ IDEA 2026.2\plugins\localization-zh
      版本: 262.10968.63  兼容: 262.10968.63 ~ 262.10968.63
  [2] C:\...\DataGrip 2026.2\plugins\localization-zh
      版本: 262.8665.272  兼容: 262.8665.272 ~ 262.8665.272
  [3] C:\...\WebStorm 2026.2\plugins\localization-zh
      版本: 262.8665.259  兼容: 262.8665.259 ~ 262.8665.259
  [0] 退出

  选择:
```

### 第 3 步：确认信息

```
=======================================================
  确认信息
=======================================================

  Rebased:       C:\迅雷下载\rebased.win(1)
  版本:          1.1.17  build 262.10968.SNAPSHOT
  类型:          ZIP 便携版
  语言包:        C:\...\IntelliJ IDEA 2026.2\plugins\localization-zh
  语言包版本:    262.10968.63
  插件安装到:    C:\迅雷下载\rebased.win(1)\config\plugins
  配置写入:      C:\迅雷下载\rebased.win(1)\config\options\ide.general.xml
  修补 until-build -> 262.*  (自动)
```

### 第 4 步：选择操作

```
  [1] 安装语言包 + 配置中文 (推荐)
  [2] 安装 + 配置 + 打包 ZIP
  [3] 仅打包 ZIP
  [4] 仅查看
  [0] 退出
```

## 执行过程

选择安装后，脚本依次执行：

1. **安全检查** — 确认 Rebased 未运行
2. **三步复制**
   - IDEA 插件 → `localization-zh-from-idea`（审计副本，保留原始 JAR）
   - 审计副本 → `localization-zh`（工作副本）
3. **修补兼容性** — 修改 JAR 内 `META-INF/plugin.xml`，`until-build` 放宽为分支通配符（如 `262.*`）
4. **配置中文** — 写入 `ide.general.xml`，设置 `selectedLocale = zh-CN`

## EXE vs ZIP

| | ZIP 便携版 | EXE 安装版 |
|---|---|---|
| 判断依据 | 无 `Uninstall.exe` | 有 `Uninstall.exe` |
| 插件安装到 | `<Rebased>\config\plugins\` | `%APPDATA%\detachhead\IdeaIC1.1\plugins\` |
| 配置写入 | `<Rebased>\config\options\` | `%APPDATA%\detachhead\IdeaIC1.1\options\` |

## 打包分发

选 `[2]` 安装 + 打包，配置完成后自动生成 `rebased.win(1)-v1.1.17-cn.zip`。解压后运行 `bin\rebased64.exe` 即为中文界面，无需额外配置。

## 备份与恢复

脚本自动备份：
- 已有插件 → `_localization-zh-backups\localization-zh-<时间戳>\`
- JAR 修补前 → `.bak-<时间戳>.jar`

## 启动后操作

启动 Rebased，进入 `File -> Settings -> Appearance -> Language`，选择 `Chinese (Simplified) / 简体中文`。

## 搜索范围

自动搜索以下目录：

- `C:\迅雷下载`
- `C:\home\app\devApp`
- `%USERPROFILE%\Downloads`
- `%USERPROFILE%\Desktop`
- `D:\`、`E:\`
- `Program Files\JetBrains`
- `Program Files (x86)\JetBrains`
- `%LOCALAPPDATA%\Programs`
- JetBrains Toolbox
- `%APPDATA%\JetBrains`

如果 Rebased 或语言包不在以上目录，选 `[2]` 手动指定路径。
