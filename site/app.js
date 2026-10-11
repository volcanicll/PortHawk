// 版本号动态关联：页面每次加载都拉取最新 Release，
// 应用发新版只需要打 tag 触发发布工作流，落地页无需重新部署。
//
// 版本获取链：Releases API（含发布日期与资产）→ releases.atom（github.com 域名，
// 不受匿名 API 限流影响）→ 页面兜底版本。下载按钮用 releases/latest/download
// 固定名直链，同样不依赖 API。
(function () {
  var REPO = "volcanicll/PortHawk";
  var FALLBACK_VERSION = "v0.1.2";
  var LATEST_DMGE = "https://github.com/" + REPO + "/releases/latest/download/PortHawk-arm64.dmg";

  var versionEl = document.getElementById("release-version");
  var btnVerEl = document.getElementById("download-version");
  var downloadBtn = document.getElementById("download-btn");
  var installLink = document.getElementById("install-link");
  var metaEl = document.getElementById("release-meta");

  downloadBtn.href = LATEST_DMGE;
  if (installLink) installLink.href = LATEST_DMGE;
  versionEl.textContent = FALLBACK_VERSION;
  btnVerEl.textContent = FALLBACK_VERSION;

  function apply(version, publishedAt) {
    versionEl.textContent = version;
    btnVerEl.textContent = version;
    if (publishedAt) {
      var date = new Date(publishedAt);
      var text = date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0") + "-" + String(date.getDate()).padStart(2, "0");
      metaEl.innerHTML =
        '最新版本 <span class="mono">' + version + "</span> · " + text +
        ' · <a href="https://github.com/' + REPO + '/releases" target="_blank" rel="noopener" style="color:var(--blue)">变更记录</a> · macOS 13+';
    }
  }

  function versionFromAtom(xml) {
    var match = xml.match(/releases\/tag\/(v[0-9][^<"\s]*)/);
    return match ? match[1] : null;
  }

  // 主路径：Releases API（带发布日期）
  fetch("https://api.github.com/repos/" + REPO + "/releases/latest")
    .then(function (res) { return res.ok ? res.json() : Promise.reject(res.status); })
    .then(function (release) {
      apply(release.tag_name || FALLBACK_VERSION, release.published_at);
      document.getElementById("deployed-note").textContent = "· 版本随 Releases 实时更新";
    })
    .catch(function () {
      // 备路径：releases.atom 不走 api.github.com，基本不会被限流
      fetch("https://github.com/" + REPO + "/releases.atom")
        .then(function (res) { return res.ok ? res.text() : Promise.reject(res.status); })
        .then(function (xml) {
          var version = versionFromAtom(xml);
          if (version) {
            apply(version, null);
            document.getElementById("deployed-note").textContent = "· 版本随 Releases 实时更新";
          }
        })
        .catch(function () { /* 保持兜底版本 */ });
    });
})();
