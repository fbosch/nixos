// 2. Profile Preparation
user_pref("browser.preferences.defaultPerformanceSettings.enabled", false);

// 3. Network Performance
user_pref("network.http.max-connections", 1800);
user_pref("network.http.max-persistent-connections-per-server", 8);
user_pref("network.http.max-urgent-start-excessive-connections-per-host", 5);
user_pref("network.http.request.max-start-delay", 5);
user_pref("network.http.pacing.requests.enabled", false);
user_pref("network.http.pacing.requests.burst", 32);
user_pref("network.http.pacing.requests.min-parallelism", 10);
user_pref("network.dnsCacheExpiration", 600);
user_pref("network.dnsCacheExpirationGracePeriod", 120);
user_pref("network.dnsCacheEntries", 10000);
user_pref("network.ssl_tokens_cache_capacity", 32768);
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("network.dns.disablePrefetch", true);
user_pref("network.dns.disablePrefetchFromHTTPS", true);
user_pref("network.prefetch-next", false);
user_pref("network.predictor.enabled", false);
user_pref("network.predictor.enable-prefetch", false);
user_pref("browser.urlbar.speculativeConnect.enabled", false);
user_pref("browser.places.speculativeConnect.enabled", false);

// 4. Memory & Caching
user_pref("javascript.options.mem.high_water_mark", 128);
user_pref("browser.cache.disk.enable", false);
user_pref("browser.cache.disk.capacity", 0);
user_pref("browser.cache.memory.capacity", 131072);
user_pref("browser.cache.disk.smart_size.enabled", false);
user_pref("browser.cache.memory.max_entry_size", 32768);
user_pref("browser.cache.disk.metadata_memory_limit", 16384);
user_pref("browser.cache.max_shutdown_io_lag", 100);
user_pref("image.mem.max_decoded_image_kb", 512000);
user_pref("image.cache.size", 10485760);
user_pref("image.mem.decode_bytes_at_a_time", 65536);
user_pref("image.mem.shared.unmap.min_expiration_ms", 90000);
user_pref("media.memory_cache_max_size", 1048576);
user_pref("media.memory_caches_combined_limit_kb", 4194304);
user_pref("media.cache_readahead_limit", 600);
user_pref("media.cache_resume_threshold", 300);
user_pref("dom.storage.default_quota", 20480);
user_pref("dom.storage.shadow_writes", true);
user_pref("browser.sessionstore.interval", 60000);
user_pref("browser.sessionhistory.max_total_viewers", 10);
user_pref("browser.sessionstore.max_tabs_undo", 10);
user_pref("browser.sessionstore.max_entries", 10);
user_pref("browser.tabs.min_inactive_duration_before_unload", 600000);

// 5. JavaScript & Content
user_pref("content.maxtextrun", 8191);
user_pref("content.interrupt.parsing", true);
user_pref("content.notify.ontimer", true);
user_pref("content.notify.interval", 50000);
user_pref("content.max.tokenizing.time", 2000000);
user_pref("content.switch.threshold", 300000);
user_pref("layout.frame_rate", -1);
user_pref("nglayout.initialpaint.delay", 5);
user_pref("gfx.content.skia-font-cache-size", 32);

// 6. GPU & Rendering
user_pref("gfx.webrender.all", true);
user_pref("gfx.webrender.enabled", true);
user_pref("gfx.webrender.compositor", true);
user_pref("gfx.webrender.precache-shaders", true);
user_pref("gfx.webrender.software", false);
user_pref("gfx.canvas.accelerated.cache-items", 32768);
user_pref("gfx.canvas.accelerated.cache-size", 4096);
user_pref("gfx.canvas.max-size", 16384);
user_pref("webgl.max-size", 16384);
user_pref("dom.webgpu.enabled", true);

// 7. UI Responsiveness
user_pref("browser.tabs.allow_transparent_browser", true);
user_pref("layout.css.backdrop-filter.enabled", true);
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("ui.submenuDelay", 0);
user_pref("dom.element.animate.enabled", true);
user_pref("general.smoothScroll", true);
user_pref("general.smoothScroll.msdPhysics.enabled", false);
user_pref("general.smoothScroll.currentVelocityWeighting", 0);
user_pref("apz.overscroll.enabled", false);
user_pref("general.smoothScroll.stopDecelerationWeighting", 1);
user_pref("general.smoothScroll.mouseWheel.durationMaxMS", 150);
user_pref("general.smoothScroll.mouseWheel.durationMinMS", 50);
user_pref("mousewheel.min_line_scroll_amount", 15);
user_pref("mousewheel.scroll_series_timeout", 10);

// 8. Processes & Tabs
user_pref("dom.ipc.processCount", 8);
user_pref("dom.ipc.keepProcessesAlive.web", 4);
user_pref("dom.ipc.processPriorityManager.backgroundUsesEcoQoS", false);
user_pref("accessibility.force_disabled", 1);

// 9. Media & Codecs
user_pref("dom.media.webcodecs.h265.enabled", true);
user_pref("media.wmf.hevc.enabled", true);
user_pref(
  "media.videocontrols.picture-in-picture.enable-when-switching-tabs.enabled",
  true,
);
user_pref("media.ffmpeg.vaapi.enabled", true);

// 10. Security & Privacy
user_pref("privacy.trackingprotection.enabled", false);
user_pref("privacy.query_stripping.enabled", false);
user_pref("privacy.query_stripping.enabled.pbmode", true);
user_pref("network.http.referer.XOriginPolicy", 0);
user_pref("network.http.referer.XOriginTrimmingPolicy", 0);
user_pref("privacy.partition.network_state", false);
user_pref("browser.safebrowsing.downloads.remote.enabled", false);

// 11. Platform-Specific
user_pref("config.trim_on_minimize", true);
user_pref("timer.auto_increase_timer_resolution", true);
user_pref("widget.wayland.opaque-region.enabled", false);
user_pref("widget.wayland.fractional-scale.enabled", true);
user_pref("gfx.wayland.hdr", false);
user_pref("widget.dmabuf.force-enabled", true);
user_pref("widget.macos.titlebar-blend", true);

// 12. Zen-Exclusive Features
user_pref("zen.widget.linux.transparency", true);
user_pref("zen.workspaces.open-new-tab-if-last-unpinned-tab-is-closed", true);
user_pref("reader.parse-on-load.enabled", false);

// 13. AI Tools & Automation
user_pref("browser.ml.chat.enabled", false);
user_pref("browser.search.suggest.enabled", false);
user_pref("browser.urlbar.suggest.searches", false);
user_pref("browser.findbar.suggest.enabled", false);
