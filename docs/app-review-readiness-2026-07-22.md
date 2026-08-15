# HarmonyOS 应用上架整改复查（2026-07-22）

## 已完成的工程整改

- 应用名称按产品决定继续使用“RustDesk Harmony”，同时在关于页、隐私政策和开源声明中明确“兼容 RustDesk 协议的第三方客户端，并非 RustDesk 官方产品”。
- 使用原创蓝色双设备互联图标，旧图标已移出打包资源目录。
- 增加首次隐私告知、同意/退出选择、应用内完整隐私政策及本地数据清除入口。
- 生成可公开部署的 `release-assets/privacy-policy.html`。
- 连接密码增加“记住连接密码”显式选择，并如实说明使用 HarmonyOS Asset Store；主机菜单增加清除密码入口。
- Server Pro 密码不持久化，访问令牌只在内存保存；增加退出 Server Pro 功能。
- 按产品要求保留 HTTP，但默认关闭。只有显式开启“允许 HTTP / 不安全 TLS（仅可信内网）”后才允许 HTTP API，并展示明文传输风险。
- 删除无功能的代理、语言、主题、二维码、录屏和指纹占位入口。
- 应用包、关于页和 oh-package 版本统一为 1.0.0；versionCode 为 1000000。
- 根目录补齐 AGPL-3.0 完整许可证和 `THIRD_PARTY_NOTICES.md`。
- 删除工程中的证书绝对路径、keyPassword 和 storePassword；发布包改为无签名产物，等待正式发布证书签名。
- 清单只申请 `ohos.permission.INTERNET`。
- Release 构建通过，包内清单确认 `debug:false`、版本 1.0.0、正确图标和 phone/tablet/2in1 设备类型。

## 发布前仍需外部材料或人工操作

这些事项不能仅靠本地代码自动完成：

1. 将 `release-assets/privacy-policy.html` 部署到开发者长期控制的公开 HTTPS 地址，并把该地址填写到华为应用市场隐私政策字段。
2. 在应用市场开发者资料中填写真实主体、支持邮箱/电话等联系方式；政策中的联系渠道依赖该信息。
3. 将本版本完整对应源码发布到公开、固定版本的 URL，并填写 `release-assets/source-code-offer.txt` 中的 `SOURCE_URL`。
4. 因应用名称仍包含 RustDesk，应准备商标/品牌授权或接受名称审核风险；第三方免责声明只能降低混淆，不能替代权利人的授权。
5. 先轮换曾经出现在旧 `build-profile.json5` 中的调试签名凭据，再使用 AppGallery Connect 正式发布证书对 release HAP 签名。
6. 在实际送审设备上回归手机、折叠屏、平板和 2in1/鸿蒙 PC；当前 Native ABI 为 arm64-v8a，提交设备范围必须与审核设备架构匹配。
7. 在应用市场后台保证名称、版本、功能介绍、截图、隐私政策和实际功能一致，不宣传已移除或未实现的能力。

## 发布产物定位

- 应用市场图标：`release-assets/app_icon_store_1024.png`
- 隐私政策网页：`release-assets/privacy-policy.html`
- 开源源码发布提示：`release-assets/source-code-offer.txt`
- 待正式签名 HAP：`release-assets/RustDesk-Harmony-1.0.0-release-unsigned.hap`
- 待正式签名 APP Pack：`release-assets/RustDesk-Harmony-1.0.0-release-unsigned.app`

本复查表示当前工程已处理可在本地完成的审核问题，不构成应用市场必然通过的保证。
