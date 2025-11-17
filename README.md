<div style="background:#050d1b; color:#e2e8f0; padding:2rem 2.5rem; border-radius:28px; box-shadow:0 30px 60px rgba(2,6,23,0.6);">
  <div align="center" style="border:1px solid rgba(248,250,252,0.1); border-radius:24px; padding:1.75rem; background:linear-gradient(145deg,#0b1222,#1e3a8a); color:#e0f2ff; margin-bottom:1.75rem;">
    <h1 style="margin-bottom:0.2rem;">微信数据库与图片密钥提取工具</h1>
    <p style="margin-top:0;">快速抽取微信 4.1+ 的数据库与缓存图片密钥</p>
    <p>
      <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License"></a>
      <a href="https://www.microsoft.com/windows"><img src="https://img.shields.io/badge/platform-Windows-lightgrey.svg" alt="Platform"></a>
      <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.9.2+-02569B.svg?logo=flutter" alt="Flutter"></a>
    </p>
  </div>

  <div style="border:1px solid rgba(251,191,36,0.3); border-radius:12px; padding:1rem 1.25rem; background:#fff9f0; color:#92400e; margin-bottom:1.75rem;">
    <strong>重要声明：</strong>
    本工具仅供技术研究与学习用途，严禁用于恶意操作。如若帮助到你，请给它一个 Star ❤️。
  </div>

  <section style="margin-bottom:2rem;">
    <h2 style="color:#f8fafc;">核心亮点</h2>
    <div style="display:grid; grid-template-columns:repeat(auto-fit,minmax(260px,1fr)); gap:1rem; margin-top:1rem;">
      <div style="border-radius:16px; padding:1rem; background:#111b2c; border:1px solid rgba(255,255,255,0.08); box-shadow:0 10px 30px rgba(15,23,42,0.4);">
        <h3 style="margin-top:0; color:#f8fafc;">自动化流程</h3>
        <ul style="margin:0; padding-left:1rem; color:#e2e8f0;">
          <li>自动附着 WeChat 进程并注入自研 DLL</li>
          <li>通过 FFI 轮询 Hook 状态与返回</li>
          <li>实时导出数据库与解密密钥</li>
        </ul>
      </div>
      <div style="border-radius:16px; padding:1rem; background:#111b2c; border:1px solid rgba(255,255,255,0.08); box-shadow:0 10px 30px rgba(15,23,42,0.4);">
        <h3 style="margin-top:0; color:#f8fafc;">研究价值</h3>
        <ul style="margin:0; padding-left:1rem; color:#e2e8f0;">
          <li>揭示 WeChat 数据存储结构</li>
          <li>辅助图片缓存反向分析</li>
          <li>与其他恢复工具协作</li>
        </ul>
      </div>
      <div style="border-radius:16px; padding:1rem; background:#111b2c; border:1px solid rgba(255,255,255,0.08); box-shadow:0 10px 30px rgba(15,23,42,0.4);">
        <h3 style="margin-top:0; color:#f8fafc;">可扩展性</h3>
        <ul style="margin:0; padding-left:1rem; color:#e2e8f0;">
          <li>Flutter 前端 + C++ 后端混合架构</li>
          <li>可复用 <code>wx_key.dll</code> 中导出接口</li>
          <li>齐全的使用与调用文档</li>
        </ul>
      </div>
    </div>
  </section>

  <section style="margin-bottom:2rem;">
    <h2 style="color:#f8fafc;">支持版本</h2>
    <p>兼容微信 4.x 系列，以下版本已实际验证：</p>
    <div style="display:flex; flex-wrap:wrap; gap:0.5rem; margin-top:0.75rem;">
      <span style="padding:0.35rem 0.85rem; border-radius:999px; background:#1f2937;">4.1.4.17</span>
      <span style="padding:0.35rem 0.85rem; border-radius:999px; background:#1f2937;">4.1.4.15</span>
      <span style="padding:0.35rem 0.85rem; border-radius:999px; background:#1f2937;">4.1.2.18</span>
      <span style="padding:0.35rem 0.85rem; border-radius:999px; background:#1f2937;">4.1.2.17</span>
      <span style="padding:0.35rem 0.85rem; border-radius:999px; background:#1f2937;">4.1.0.30</span>
      <span style="padding:0.35rem 0.85rem; border-radius:999px; background:#1f2937;">4.0.5.17</span>
    </div>
  </section>

  <section style="margin-bottom:2rem;">
    <h2 style="color:#f8fafc;">快速启动</h2>
    <div style="display:grid; grid-template-columns:repeat(auto-fit,minmax(280px,1fr)); gap:1rem;">
      <div style="border-radius:16px; background:#111b2c; padding:1.25rem; border:1px solid rgba(255,255,255,0.08); box-shadow:0 15px 35px rgba(15,23,42,0.5);">
        <h3 style="margin-top:0; color:#f8fafc;">发布版</h3>
        <ol style="padding-left:1.2rem; color:#e2e8f0;">
          <li>访问 <a href="https://github.com/ycccccccy/wx_key/releases" style="color:#38bdf8;">Releases</a> 页面。</li>
          <li>下载最新压缩包并解压。</li>
          <li>运行 <code>wx_key.exe</code>。</li>
        </ol>
        <p style="margin:0;">无需额外依赖即可运行。</p>
      </div>
      <div style="border-radius:16px; background:#111b2c; padding:1.25rem; border:1px solid rgba(255,255,255,0.08); box-shadow:0 15px 35px rgba(15,23,42,0.5);">
        <h3 style="margin-top:0; color:#f8fafc;">注意事项</h3>
        <ul style="color:#e2e8f0;">
          <li>工具目录禁止包含中文路径；DLL 加载会失败。</li>
          <li>确保微信已登录且处于前台。</li>
          <li>提取图片密钥时按流程操作以触发缓存。</li>
        </ul>
      </div>
    </div>
  </section>

  <section style="margin-bottom:2rem;">
    <h2 style="color:#f8fafc;">图片密钥获取流程</h2>
    <ol style="padding-left:1.2rem; color:#e2e8f0;">
      <li>微信登录后立即继续操作。</li>
      <li>打开朋友圈里未浏览的图片以触发缓存。</li>
      <li>返回工具点击「开始抓取」获取密钥。</li>
    </ol>
  </section>

  <section style="margin-bottom:2rem;">
    <h2 style="color:#f8fafc;">目录结构</h2>
    <pre style="background:#0b1222; padding:1rem; border-radius:16px; border:1px solid rgba(255,255,255,0.05); overflow-x:auto;"><code>wx_key/
├── lib/                                  # Flutter 前端（状态、服务、窗口）
│   ├── main.dart                         # UI 驱动与状态管理
│   ├── services/                          # FFI / 密钥 / 日志
│   └── widgets/                           # 自定义控件与对话框
├── assets/dll/wx_key.dll                 # 控制器 DLL
├── wx_key/                               # C++ 原生项目（Visual Studio）
│   ├── include/                          # Hook、IPC、Shellcode 头文件
│   ├── src/                              # hook_controller、remote_scanner 等实现
│   └── wx_key.vcxproj                    # 工程配置
└── build/windows/...                     # Flutter 构建产物
</code></pre>
  </section>

  <section style="margin-bottom:2rem;">
    <h2 style="color:#f8fafc;">DLL 扩展调用</h2>
    <p style="color:#e2e8f0;">需要复用 <code>wx_key.dll</code>（如自行获取 PID 后直接调用导出函数）时，请参考 <a href="docs/dll_usage.md">docs/dll_usage.md</a>。</p>
  </section>

  <section style="margin-bottom:2rem;">
    <h2 style="color:#f8fafc;">开发构建</h2>
    <pre style="background:#0b1222; padding:1rem; border-radius:16px; border:1px solid rgba(255,255,255,0.05); overflow-x:auto; color:#e2e8f0;"><code>git clone https://github.com/ycccccccy/wx_key.git
cd wx_key
flutter pub get
flutter build windows --release
# 产物：build/windows/runner/Release/wx_key.exe
</code></pre>
  </section>

  <section style="margin-bottom:2rem;">
    <h2 style="color:#f8fafc;">许可证与免责声明</h2>
    <h3 style="color:#f8fafc;">许可证</h3>
    <p style="color:#e2e8f0;">采用 MIT 许可证，详见 <a href="LICENSE">LICENSE</a>。</p>
    <h3 style="color:#f8fafc;">免责声明</h3>
    <ul style="color:#e2e8f0;">
      <li>使用者需对任何后果与责任独立承担。</li>
      <li>请确保行为符合法律法规与当地政策。</li>
      <li>严禁将本工具用于商业或恶意用途。</li>
    </ul>
  </section>

  <section style="margin-bottom:2rem;">
    <h2 style="color:#f8fafc;">贡献指南</h2>
    <ol style="padding-left:1.2rem; color:#e2e8f0;">
      <li>Fork 仓库并创建新分支。</li>
      <li>开发功能并提交有意义的变更。</li>
      <li>推送至远端，创建 Pull Request。</li>
    </ol>
  </section>

  <section style="margin-bottom:2rem;">
    <h2 style="color:#f8fafc;">致谢</h2>
    <ul style="color:#e2e8f0;">
      <li><a href="https://github.com/recarto404/WxDatDecrypt">WxDatDecrypt</a> — imagekey 思路参考。</li>
    </ul>
  </section>

  <section style="margin-bottom:2rem;">
    <h2 style="color:#f8fafc;">Star History</h2>
    <p><a href="https://www.star-history.com/#ycccccccy/wx_key&type=date&legend=top-left"><img src="https://api.star-history.com/svg?repos=ycccccccy/wx_key&type=date&legend=top-left" alt="Star History Chart"></a></p>
  </section>

  <footer style="border-top:1px solid rgba(255,255,255,0.1); padding-top:1rem; text-align:center;">
    <strong>请负责任地使用本工具，遵守相关法律法规</strong>
    <p>Made for educational purposes ❤️</p>
  </footer>
</div>
