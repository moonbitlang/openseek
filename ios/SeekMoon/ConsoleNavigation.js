// This script runs only in WebKit's isolated client world. The hosted console
// owns the catalog, device connections and routing; reuse its mounted controls.
(() => {
    function isConsole() {
        return location.origin === 'https://seekmoon.moonbitlang.com' &&
            /^\/(cloud(?:\/|$)|device\/)/.test(location.pathname);
    }
    if (!isConsole() || document.documentElement.hasAttribute('data-seekmoon-account')) return;

    const bridge = window.webkit.messageHandlers.consoleNavigation;
    const cloudGroup = 'aside .sidebar-group-content[id^="section:cloud.chats:"]';
    const toggle = '.app.sidebar-collapsed button.sidebar-toggle';
    const chinese = navigator.language.startsWith('zh');
    const navLabel = chinese ? '导航' : 'Navigation';
    const style = document.createElement('style');
    style.textContent = mobile.style;
    document.head.append(style);

    let bypass = false;
    let lastGroup;
    let lastCatalog;
    let nativeAnchor;
    let lastPlacement;
    let lastGate;
    let announcedReady = false;
    let compactContent;

    function loginGate() {
        const cloud = document.querySelector('.cloud-home .empty');
        return Boolean(cloud?.querySelector(':scope > button.primary') && !cloud.querySelector('.empty-detail')) ||
            Boolean(document.querySelector('.portal-card a[href^="/v2/auth/login"]'));
    }

    function signedInCloudGroup() {
        const cloud = document.querySelector(cloudGroup);
        return cloud && !cloud.querySelector('.cloud-sign-in') && !document.querySelector('.cloud-home') ? cloud : null;
    }

    function conversations(container) {
        return Array.from(container.querySelectorAll('button.conversation-open[id]'))
            .filter(button => !button.closest('.conversation-children'))
            .map(button => ({
                id: button.id, title: button.textContent.trim(), current: button.getAttribute('aria-current') === 'true'
            }));
    }

    function workspaceRows() {
        return Array.from(document.querySelectorAll('aside .workspace-row'));
    }

    function projectContent(row) {
        const id = row.querySelector('button.workspace-disclosure')?.getAttribute('aria-controls');
        return id && document.getElementById(id);
    }

    function newWorkspaceChat(row) {
        return row.querySelector('.workspace-actions button.row-archive:not(.workspace-menu-button)');
    }

    function cloudChatTools() {
        const section = document.querySelector(cloudGroup)?.closest('.sidebar-section.sessions');
        const index = Array.from(document.querySelectorAll('aside .sidebar-section.sessions')).indexOf(section);
        return document.querySelectorAll('aside .sidebar-list-tools')[index];
    }

    function cloudImportButton(tools) {
        const labels = ['Import', '导入', '匯入', 'Importar', 'インポート',
            'Import conversation', '导入对话', '匯入對話', 'Importar conversación', '会話をインポート'];
        return Array.from(tools?.querySelectorAll('button') || []).find(button =>
            labels.includes(button.getAttribute('aria-label') || button.title || button.textContent.trim()));
    }

    // The hosted footer exposes translated labels, without stable tool IDs.
    const toolLabels = {
        skills: ['Skills', 'Habilidades', '技能', 'スキル'],
        scheduled: ['Scheduled', 'Tareas programadas', '定时任务', '定時任務', 'スケジュールタスク'],
        settings: ['Settings', 'Configuración', '设置', '設定'],
        download: ['Download apps', 'Descargar las apps', '下载客户端', '下載用戶端', 'アプリをダウンロード']
    };

    function sidebarTools() {
        return Array.from(document.querySelectorAll('aside .sidebar-footer button.sidebar-button:not(.console-account)'), button => {
            const title = button.textContent.trim();
            const id = Object.keys(toolLabels).find(key => toolLabels[key].includes(title)) ?? title;
            button.toggleAttribute('data-ios-download', id === 'download');
            return {id, title, button};
        }).filter(tool => tool.id !== 'download');
    }

    function avatarURL() {
        const src = document.querySelector('aside .console-account img')?.getAttribute('src');
        if (!src || !URL.canParse(src, location.href)) return null;
        const url = new URL(src, location.href);
        return url.protocol === 'https:' && !url.username && !url.password ? url.href : null;
    }

    function accountIdentity() {
        return {name: document.querySelector('aside .console-account .console-login')?.textContent.trim() || '', avatar: avatarURL()};
    }

    function headerButtons(content) {
        if (!content) return [];
        return Array.from(content.querySelectorAll(
            ':scope > main > .topbar button, :scope > button.right-panel-toggle'
        )).filter(button => !button.disabled && !button.classList.contains('hidden') &&
            button.getClientRects().length && headerLabel(button));
    }

    const headerLabel = button => button.getAttribute('aria-label') || button.title || button.textContent.trim();

    function catalog() {
        const cloud = signedInCloudGroup();
        if (!cloud) return null;
        const status = cloud.querySelector('.conversation-row.placeholder');
        const projects = workspaceRows().flatMap(row => {
            const content = projectContent(row);
            const title = row.querySelector('.workspace-disclosure .sidebar-label')?.textContent.trim();
            if (!content || !title) return [];
            const create = newWorkspaceChat(row);
            return [{
                id: content.id, title,
                host: row.querySelector('.workspace-host-name')?.textContent.trim() || '',
                offline: Boolean(row.querySelector('.workspace-host-status.offline')),
                chats: conversations(content), canCreate: Boolean(create && !create.disabled),
                hasMore: Boolean(content.querySelector('.project-show-more'))
            }];
        });
        const tools = cloudChatTools();
        const create = tools?.querySelector('button:has(.codicon-add)');
        const importButton = cloudImportButton(tools);
        const identity = accountIdentity();
        return {
            chats: conversations(cloud), projects, canCreate: Boolean(create && !create.disabled),
            canImport: Boolean(importButton && !importButton.disabled),
            notice: status?.querySelector('.sidebar-label')?.textContent.trim() || '',
            canRetry: Boolean(status?.querySelector('button:enabled')),
            tools: sidebarTools().map(({id, title, button}) => ({id, title, enabled: !button.disabled})),
            avatar: identity.avatar, account: identity.name,
            inWorkspace: Boolean(document.querySelector('aside .workspace-row.active')) || location.pathname.startsWith('/device/')
        };
    }

    function update(sidebarChanged) {
        if (!isConsole()) return;
        if (!announcedReady && document.body?.innerText.trim()) {
            announcedReady = true;
            bridge.postMessage({event: 'ready'});
        }
        const gate = loginGate();
        if (gate !== lastGate) {
            lastGate = gate;
            bridge.postMessage({event: 'login', visible: gate});
        }
        // A restored device can be offline before its sidebar even mounts.
        const portal = document.querySelector('.portal-card:has(button.secondary)');
        if (portal && location.pathname.startsWith('/device/') && !portal.querySelector('a[href="/cloud"]')) {
            const home = document.createElement('a');
            home.href = '/cloud';
            home.className = 'portal-button-link';
            home.textContent = chinese ? '返回云端对话' : 'Back to cloud chats';
            portal.append(home);
        }
        // Strip the install promotion even when the hosted sidebar is the fallback.
        if (!signedInCloudGroup()) sidebarTools();
        const button = document.querySelector(toggle);
        const cloud = signedInCloudGroup();
        if (button && cloud &&
            (!button.hasAttribute('data-ios-navigation') || button.getAttribute('aria-label') !== navLabel)) {
            button.dataset.iosNavigation = '';
            button.setAttribute('aria-label', navLabel);
            button.title = navLabel;
        }
        // Cache the catalog before a native edge pan starts, so the drawer can
        // track the finger immediately. A covered toggle belongs to a background page.
        const rect = button?.getBoundingClientRect();
        const reachable = rect && button.contains(document.elementFromPoint(rect.x + rect.width / 2, rect.y + rect.height / 2));
        // A dialog makes the chat inert, but its header and composer are still
        // visible behind the backdrop. Keep layout tied to the mounted chat.
        const content = mobile.nativeMenu && cloud && button ? button.parentElement.querySelector(
            ':scope > .content:not(.panel-open):has(> main > .topbar:not(.codex-topbar)):has(> main > :is(#transcript, .transcript, .composer))'
        ) : null;
        if (content !== compactContent) {
            compactContent?.removeAttribute('data-ios-chat-header');
            content?.setAttribute('data-ios-chat-header', '');
            compactContent = content;
        }
        const dialogs = document.querySelectorAll('dialog[open]');
        const covered = !!content && dialogs.length === 1 &&
            dialogs[0].matches(':modal:not(#management-dialog, #skill-detail-dialog)');
        document.documentElement.toggleAttribute('data-ios-chat-dialog', covered);
        updateSurfaces();
        const behindWeb = covered && document.documentElement.hasAttribute('data-ios-glass-composer');
        const group = reachable || behindWeb ? cloud : null;
        const viewport = window.visualViewport;
        const anchor = mobile.nativeMenu && group && !button.disabled &&
            consoleViewportFits() && !viewport?.offsetTop && !viewport?.offsetLeft ? button : null;
        if (anchor !== nativeAnchor) {
            if (nativeAnchor) {
                nativeAnchor.removeAttribute('data-ios-native-menu');
                nativeAnchor.removeAttribute('aria-hidden');
                nativeAnchor.removeAttribute('tabindex');
            }
            nativeAnchor = anchor;
            if (anchor) {
                anchor.setAttribute('data-ios-native-menu', '');
                anchor.setAttribute('aria-hidden', 'true');
                anchor.tabIndex = -1;
            }
        }
        const commands = reachable ? headerButtons(content).map(headerLabel) : [];
        const menu = anchor ? {x: rect.x, y: rect.y, size: rect.width, covered: behindWeb} : null;
        const theme = document.documentElement.dataset.theme || '';
        const placement = JSON.stringify([menu, theme, commands]);
        if (group === lastGroup && (!group || !sidebarChanged) && placement === lastPlacement) return;
        lastGroup = group;
        const data = group ? catalog() : null;
        const serialized = JSON.stringify(data);
        if (serialized !== lastCatalog || placement !== lastPlacement) {
            lastCatalog = serialized;
            lastPlacement = placement;
            bridge.postMessage({event: 'update', data, menu, theme, commands});
        }
    }

    document.addEventListener('click', event => {
        if (bypass || !isConsole() || !event.target.closest?.(toggle)) return;
        const data = catalog();
        if (!data) return; // Changed or unsupported web layout keeps its own drawer.
        event.preventDefault();
        event.stopImmediatePropagation();
        lastCatalog = JSON.stringify(data);
        bridge.postMessage({event: 'open', data});
    }, true);

    window.consoleNavigationAction = (action, id) => {
        if (!isConsole()) return false;
        if (action === 'header') {
            if (!compactContent?.isConnected || document.querySelector('dialog[open]')) return false;
            const button = headerButtons(compactContent).find(item => headerLabel(item) === id);
            if (!button) return false;
            button.click();
            return true;
        }
        if (action === 'webSidebar') {
            const button = document.querySelector(toggle);
            if (!button) return false;
            bypass = true;
            try { button.click(); } finally { bypass = false; }
            return true;
        }
        const row = workspaceRows().find(row => projectContent(row)?.id === id);
        let button;
        switch (action) {
        case 'chat':
            button = document.getElementById(id);
            if (!button?.matches('aside button.conversation-open')) return false;
            break;
        case 'tool': button = sidebarTools().find(item => item.id === id)?.button; break;
        case 'newCloud': button = cloudChatTools()?.querySelector('button:has(.codicon-add)'); break;
        case 'importCloud': button = cloudImportButton(cloudChatTools()); break;
        case 'newWork': button = row && newWorkspaceChat(row); break;
        case 'more': button = row && projectContent(row).querySelector('.project-show-more'); break;
        case 'retry': button = document.querySelector(cloudGroup)?.querySelector('.conversation-row.placeholder button'); break;
        default: return false;
        }
        if (!button || button.disabled) return false;
        // showModal restores DOM focus on dismissal. The native drawer has
        // already dismissed the keyboard, so return to its anchor, not the draft.
        if (action === 'importCloud' || (action === 'tool' && id === 'skills')) {
            document.querySelector(toggle)?.focus({preventScroll: true});
        }
        if (action === 'tool' && id === 'settings') window.consoleSettingsOverview();
        button.click();
        return true;
    };

    let frame;
    let sidebarChanged = false;
    function scheduleUpdate() {
        if (frame) return;
        frame = requestAnimationFrame(() => {
            frame = null;
            update(sidebarChanged);
            sidebarChanged = false;
        });
    }
    window.addEventListener('resize', scheduleUpdate);
    window.visualViewport?.addEventListener('resize', scheduleUpdate);
    window.visualViewport?.addEventListener('scroll', scheduleUpdate);
    document.addEventListener('toggle', scheduleUpdate, true);
    new MutationObserver(records => {
        if (records.every(record => record.target.parentElement?.closest('#transcript'))) return;
        sidebarChanged ||= records.some(record =>
            (record.target.nodeType === Node.ELEMENT_NODE ? record.target : record.target.parentElement)?.closest('aside')
        );
        scheduleUpdate();
    }).observe(document.documentElement, {
        childList: true, subtree: true, characterData: true, attributes: true,
        attributeFilter: ['class', 'hidden', 'aria-current', 'disabled', 'src', 'open', 'data-theme',
            'aria-selected', 'aria-checked', 'aria-pressed', 'aria-expanded', 'title', 'aria-label']
    });
    const updateSurfaces = installConsoleSurfaces(mobile, bridge, scheduleUpdate, accountIdentity);
    update(true);
})();
