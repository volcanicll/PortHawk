// 版本号动态关联：页面每次加载都从 GitHub Releases 拉最新版本，
// 应用发新版只需要打 tag 触发发布工作流，落地页无需重新部署。
// API 失败（离线/限流）时回退到页面里写死的兜底版本。
(function () {
  var REPO = "volcanicll/PortHawk";
  var FALLBACK_VERSION = "v0.1.0";

  var versionEl = document.getElementById("release-version");
  var btnVerEl = document.getElementById("download-version");
  var downloadBtn = document.getElementById("download-btn");
  var installLink = document.getElementById("install-link");
  var metaEl = document.getElementById("release-meta");

  function apply(version, assetUrl, publishedAt) {
    versionEl.textContent = version;
    btnVerEl.textContent = version;
    if (assetUrl) {
      downloadBtn.href = assetUrl;
      installLink.href = assetUrl;
    }
    if (publishedAt) {
      var date = new Date(publishedAt);
      var text = date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0") + "-" + String(date.getDate()).padStart(2, "0");
      metaEl.innerHTML =
        '最新版本 <span class="mono">' + version + "</span> · " + text +
        ' · <a href="https://github.com/' + REPO + '/releases" target="_blank" rel="noopener" style="color:var(--blue)">变更记录</a> · macOS 13+';
    }
  }

  fetch("https://api.github.com/repos/" + REPO + "/releases/latest")
    .then(function (res) { return res.ok ? res.json() : Promise.reject(res.status); })
    .then(function (release) {
      var version = release.tag_name || FALLBACK_VERSION;
      // 优先给 arm64 DMG，其次 zip，最后退到 release 页
      var assetUrl = null;
      (release.assets || []).forEach(function (asset) {
        if (/arm64\.dmg$/.test(asset.name)) assetUrl = asset.browser_download_url;
      });
      if (!assetUrl) {
        (release.assets || []).forEach(function (asset) {
          if (/arm64\.zip$/.test(asset.name)) assetUrl = asset.browser_download_url;
        });
      }
      apply(version, assetUrl, release.published_at);
      document.getElementById("deployed-note").textContent = "· 版本随 Releases 实时更新";
    })
    .catch(function () {
      apply(FALLBACK_VERSION, null, null);
    });
})();
