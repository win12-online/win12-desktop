<h1 align="center">Win12 Desktop</h1>

<p align="center">
  <strong>将 Win12 Online 带到桌面的独立客户端。</strong>
</p>

<p align="center">
  <a href="https://github.com/win12-online/win12-desktop/releases/latest"><img src="https://img.shields.io/github/v/release/win12-online/win12-desktop?label=%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC&style=flat-square" alt="最新版本"></a>
  <a href="https://github.com/win12-online/win12-desktop/stargazers"><img src="https://img.shields.io/github/stars/win12-online/win12-desktop?style=flat-square" alt="GitHub Stars"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/win12-online/win12-desktop?style=flat-square" alt="许可证"></a>
</p>

<p align="center">
  <a href="https://win12-wiki.lingbopro.qzz.io/zh/desktop/">使用文档</a>
  &nbsp;&middot;&nbsp;
  <a href="https://github.com/win12-online/win12">网页版</a>
  &nbsp;&middot;&nbsp;
  <a href="https://github.com/win12-online/win12-desktop/releases/latest">下载客户端</a>
  &nbsp;&middot;&nbsp;
  <a href="https://github.com/win12-online/win12-desktop/issues">问题反馈</a>
</p>

## 简介

Win12 Desktop 是 [Win12 Online](https://github.com/win12-online/win12) 的桌面客户端，使用 [Tauri](https://tauri.app/) 将项目打包为独立应用。它保留 Win12 Online 的桌面交互与应用体验，并提供更贴近原生应用的窗口化使用方式。

> [!NOTE]
> Win12 是非商业性的开源兴趣项目，与 Microsoft Corporation 及其关联实体没有隶属、赞助、授权或认可关系。项目界面为基于公开资料的独立再创作，仅供学习与技术研究使用。

## 下载

从 [GitHub Releases](https://github.com/win12-online/win12-desktop/releases/latest) 获取最新安装包。Linux 用户也可通过 AUR 安装：

```bash
yay -S win12-desktop-bin
```

国内网络环境可使用 [南京大学开源镜像站](https://mirror.nju.edu.cn/github-release/win12-online/win12-desktop/) 下载发布文件。

## 客户端预览

![Win12 Desktop 在 Linux 上运行，展示开始菜单与桌面](images/linux-1.png)

_开始菜单与桌面_

![Win12 Desktop 在 Linux 上运行，展示文件管理器与系统界面](images/linux-2.png)

_窗口化应用体验_

## 开发

本仓库通过 Git 子模块引入 Win12 Online 本体，克隆时请一并拉取子模块：

```bash
git clone --recurse-submodules https://github.com/win12-online/win12-desktop.git
cd win12-desktop
```

若仓库已克隆，可补充初始化：

```bash
git submodule update --init --recursive
```

安装前端依赖：

```bash
npm install
```

启动开发环境时，需要分别启动前端服务与 Tauri 应用：

```bash
# 终端 1：启动 Vite
npm run dev

# 终端 2：启动桌面客户端
npm run tauri dev
```

若系统代理影响 Tauri 启动，可在第二个终端使用：

```bash
env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u all_proxy npm run tauri dev
```

构建发布版本：

```bash
npm run tauri build
```

## 相关项目

- [Win12 Online](https://github.com/win12-online/win12)：Win12 网页版主项目
- [Win12 Wiki](https://win12-wiki.lingbopro.qzz.io/zh/desktop/)：桌面版使用文档
- [Win12 Desktop Releases](https://github.com/win12-online/win12-desktop/releases)：历史版本与安装包
- [Win12 Desktop Homebrew Tap](https://github.com/freedom-323/homebrew-win12-desktop)：Win12 Desktop 的 Homebrew 安装仓库

## 许可证

本仓库以 [Eclipse Public License 2.0](LICENSE) 发布。Win12 Online 的代码、媒体和文字内容适用的具体许可与附加条款，请参见[网页版开源声明](https://github.com/win12-online/win12#%E5%BC%80%E6%BA%90%E5%A3%B0%E6%98%8E)。
