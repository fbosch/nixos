// Floorp declarative baseline (curated stable prefs)

// Browser behavior
user_pref("browser.contentblocking.category", "strict");
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.privatebrowsing.autostart", true);
user_pref("browser.startup.homepage", "https://mullvad.net/en/check");
user_pref("browser.tabs.closeWindowWithLastTab", false);
user_pref("browser.toolbars.bookmarks.visibility", "never");
user_pref("intl.locale.requested", "en");

// Network + WebRTC
user_pref("network.dns.disablePrefetch", true);
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("network.prefetch-next", false);
// Delegate URL2App links to the registered system protocol handler.
user_pref("network.protocol-handler.expose.x-url2app", false);
user_pref("network.protocol-handler.external.x-url2app", true);
user_pref("network.protocol-handler.warn-external.x-url2app", false);
user_pref("network.trr.custom_uri", "https://dns.nextdns.io/24219a");
user_pref("media.peerconnection.ice.default_address_only", true);
user_pref("media.peerconnection.ice.no_host", true);
user_pref("media.peerconnection.ice.proxy_only_if_behind_proxy", true);

// Privacy
user_pref("privacy.annotate_channels.strict_list.enabled", true);
user_pref("privacy.bounceTrackingProtection.mode", 1);
user_pref("privacy.clearOnShutdown_v2.browsingHistoryAndDownloads", false);
user_pref("privacy.clearOnShutdown_v2.formdata", true);
user_pref("privacy.fingerprintingProtection", true);
user_pref("privacy.globalprivacycontrol.enabled", true);
user_pref("privacy.query_stripping.enabled", true);
user_pref("privacy.query_stripping.enabled.pbmode", true);
user_pref("privacy.sanitize.sanitizeOnShutdown", true);
user_pref("privacy.trackingprotection.emailtracking.enabled", true);
user_pref("privacy.trackingprotection.enabled", true);
user_pref("privacy.trackingprotection.socialtracking.enabled", true);

// Floorp UI and features
user_pref("floorp.browser.ssb.config", "{\"showToolbar\":true}");
user_pref("floorp.browser.ssb.enabled", true);
user_pref("floorp.browser.tabs.openNewTabPosition", -1);
user_pref("floorp.design.configs", "{\"globalConfigs\":{\"userInterface\":\"photon\",\"faviconColor\":false,\"appliedUserJs\":\"\"},\"tabbar\":{\"tabbarStyle\":\"horizontal\",\"tabbarPosition\":\"default\",\"multiRowTabBar\":{\"maxRowEnabled\":false,\"maxRow\":3}},\"tab\":{\"tabScroll\":{\"enabled\":false,\"reverse\":false,\"wrap\":false},\"tabMinHeight\":30,\"tabMinWidth\":76,\"tabPinTitle\":false,\"tabDubleClickToClose\":false,\"tabOpenPosition\":-1},\"uiCustomization\":{\"navbar\":{\"position\":\"top\",\"searchBarTop\":false},\"display\":{\"disableFullscreenNotification\":false,\"deleteBrowserBorder\":false},\"special\":{\"optimizeForTreeStyleTab\":false,\"hideForwardBackwardButton\":false,\"stgLikeWorkspaces\":false},\"multirowTab\":{\"newtabInsideEnabled\":false},\"bookmarkBar\":{\"focusExpand\":false,\"position\":\"top\"},\"qrCode\":{\"disableButton\":false},\"disableFloorpStart\":true}}");
user_pref("floorp.keyboardshortcut.config", "{\"enabled\":true,\"shortcuts\":{}}");
user_pref("floorp.keyboardshortcut.enabled", true);
user_pref("floorp.mousegesture.config", "{\"enabled\":false,\"rockerGesturesEnabled\":true,\"wheelGesturesEnabled\":true,\"sensitivity\":40,\"showTrail\":true,\"showLabel\":true,\"trailColor\":\"#37ff00\",\"trailWidth\":6,\"contextMenu\":{\"minDistance\":12,\"preventionTimeout\":200},\"actions\":[{\"pattern\":[\"left\"],\"action\":\"gecko-back\"},{\"pattern\":[\"right\"],\"action\":\"gecko-forward\"},{\"pattern\":[\"up\",\"down\"],\"action\":\"gecko-reload\"},{\"pattern\":[\"down\",\"right\"],\"action\":\"gecko-close-tab\"},{\"pattern\":[\"down\",\"up\"],\"action\":\"gecko-open-new-tab\"},{\"pattern\":[\"up\"],\"action\":\"gecko-scroll-to-top\"},{\"pattern\":[\"down\"],\"action\":\"gecko-scroll-to-bottom\"},{\"pattern\":[\"left\",\"down\"],\"action\":\"gecko-scroll-up\"},{\"pattern\":[\"right\",\"down\"],\"action\":\"gecko-scroll-down\"}]}");
user_pref("floorp.mousegesture.enabled", false);
user_pref("floorp.newtab.configs", "{\"components\":{\"topSites\":true,\"clock\":true,\"searchBar\":true,\"firefoxLayout\":true},\"background\":{\"type\":\"none\",\"customImage\":null,\"fileName\":null,\"folderPath\":null,\"selectedFloorp\":null,\"slideshowEnabled\":false,\"slideshowInterval\":30},\"searchBar\":{\"searchEngine\":\"default\"},\"topSites\":{\"pinned\":[{\"url\":\"https://www.cube-soft.jp/\",\"title\":\"Cubesoft (Sponsor)\"},{\"url\":\"https://docs.floorp.app/docs/features/\",\"title\":\"Floorp Support\"}],\"blocked\":[]}}");
user_pref("floorp.panelSidebar.config", "{\"autoUnload\":false,\"position_start\":true,\"globalWidth\":400,\"displayed\":true,\"webExtensionRunningEnabled\":false}");
user_pref("floorp.panelSidebar.data", "{\"data\":[{\"id\":\"default-panel-bookmarks\",\"url\":\"floorp//bookmarks\",\"width\":0,\"type\":\"static\"},{\"id\":\"default-panel-history\",\"url\":\"floorp//history\",\"width\":0,\"type\":\"static\"},{\"id\":\"default-panel-downloads\",\"url\":\"floorp//downloads\",\"width\":0,\"type\":\"static\"},{\"id\":\"default-panel-notes\",\"url\":\"floorp//notes\",\"width\":0,\"type\":\"static\"},{\"id\":\"default-panel-translate-google-com\",\"url\":\"https://translate.google.com\",\"width\":0,\"userContextId\":null,\"zoomLevel\":null,\"type\":\"web\"},{\"id\":\"default-panel-docs-floorp-app\",\"url\":\"https://docs.floorp.app/docs/features/\",\"width\":0,\"userContextId\":null,\"zoomLevel\":null,\"type\":\"web\"}]}");
user_pref("floorp.panelSidebar.enabled", false);
user_pref("floorp.splitView.config", "{\"layout\":\"horizontal\",\"maxPanes\":4}");
user_pref("floorp.splitView.paneSizes", "{\"flexRatios\":[0.5,0.5],\"gridColRatio\":0.5,\"gridRowRatio\":0.5}");
user_pref("floorp.workspaces.enabled", false);
user_pref("floorp.workspaces.pending-exit-from-workspace-empty", false);
user_pref("floorp.workspaces.v4.config", "{\"manageOnBms\":false,\"showWorkspaceNameOnToolbar\":true,\"closePopupAfterClick\":false,\"exitOnLastTabClose\":false}");
user_pref("floorp.workspaces.v4.store", "{\"defaultID\":\"aedf6767-c00f-405f-bbe5-06e9490549a4\",\"data\":[[\"aedf6767-c00f-405f-bbe5-06e9490549a4\",{\"name\":\"New Workspace (0)\",\"icon\":null,\"userContextId\":0}]],\"order\":[\"aedf6767-c00f-405f-bbe5-06e9490549a4\"]}");
user_pref("floorp.zenmode.enabled", false);

// Sidebar + chrome tweaks
user_pref("sidebar.visibility", "hide-sidebar");
user_pref("userChrome.hidden.urlbar_iconbox", true);
