// Loaded in the isolated console world. UIKit provides the glass behind the
// editor, while WebKit retains the caret, selection, IME and attachment actions.
function consoleViewportFits() {
    // WebKit can still report scale > 1 after dismissing skill search even
    // when the full layout fits. Match native controls to the visible width.
    const viewport = window.visualViewport;
    return !viewport || Math.abs(viewport.width - document.documentElement.clientWidth) < 1;
}
function installConsoleSurfaces(mobile, bridge, scheduleUpdate, accountIdentity) {
    const root = document.documentElement;
    installOutgoingPreview();
    const media = matchMedia('(prefers-color-scheme: dark)');
    media.addEventListener('change', scheduleUpdate);
    let composer, lastComposer, lastSettings, lastSkills;
    const resize = new ResizeObserver(scheduleUpdate);
    function channels(cssColor) {
        const rgb = cssColor.match(/^rgb\((\d+),\s*(\d+),\s*(\d+)\)$/);
        return rgb ? rgb.slice(1).map(Number) : null;
    }
    function updateComposer() {
        if (!mobile.glassMenu) return;
        const card = document.querySelector('#app main > .composer .composer-inner:has(textarea#task)');
        if (composer !== card) {
            if (composer) resize.unobserve(composer);
            composer = card;
            if (card) resize.observe(card);
        }
        const r = card?.getBoundingClientRect();
        const covered = root.hasAttribute('data-ios-chat-dialog');
        const active = r?.width > 0 && r.height > 0 && (covered || !document.querySelector('dialog[open]')) &&
            consoleViewportFits();
        // Use the hosted canvas color in the safe areas and under the material.
        // This probe still resolves the theme after the web canvas is transparent.
        let data = null;
        if (active) {
            const color = channels(getComputedStyle(card, '::before').color);
            if (color) {
                const theme = ['light', 'dark'].includes(root.dataset.theme) ? root.dataset.theme :
                    media.matches ? 'dark' : 'light';
                // The keyboard changes the viewport height. Its bottom gap stays
                // the same even while UIKit and WebKit are on different frames.
                const gap = card.closest('#app').getBoundingClientRect().bottom - r.bottom;
                data = {x: r.x, bottom: gap,
                    width: r.width, height: r.height, color, theme,
                    dialogDim: covered ? parseFloat(getComputedStyle(root).getPropertyValue('--ios-dialog-dim')) / 100 : null,
                    appearance: root.dataset.theme || 'system'};
            }
        }
        root.toggleAttribute('data-ios-glass-composer', !!data);
        const key = JSON.stringify(data);
        if (lastComposer !== key) {
            lastComposer = key;
            bridge.postMessage({event: 'composer', data});
        }
    }

    // Only represent recognized settings forms. Retain the live elements for
    // actions so an item which disappears or becomes disabled cannot be invoked.
    const identities = new WeakMap();
    const pageID = crypto.randomUUID();
    let nextID = 0;
    const actions = new Map();
    function controlID(node) {
        if (!identities.has(node)) identities.set(node, pageID + '-' + ++nextID);
        const id = identities.get(node);
        actions.set(id, node);
        return id;
    }
    const label = node => node?.textContent.trim() || '';
    const buttonData = b => ({
        id: controlID(b), sourceID: b.id, label: b.title && b.matches('[role=option]') ? b.title :
            label(b) || b.getAttribute('aria-label') || b.title || '',
        kind: b.matches('[role=switch]') ? 'toggle' : b.matches('[aria-haspopup=listbox]') ? 'picker' :
            b.hasAttribute('aria-pressed') ? 'segment' : 'button',
        selected: ['aria-selected','aria-checked','aria-pressed'].some(attr => b.getAttribute(attr) === 'true'),
        disabled: b.disabled, danger: b.classList.contains('danger')
    });
    let overview = false;
    let selectAccount = false;
    window.consoleSettingsOverview = () => {
        overview = true;
        selectAccount = true;
        scheduleUpdate();
    };
    document.addEventListener('close', event => {
        if (event.target.id === 'management-dialog' && !event.target.open) {
            overview = false;
            selectAccount = false;
            scheduleUpdate();
        }
    }, true);

    function settings() {
        const dialog = document.querySelector('#management-dialog[open]');
        if (!dialog || document.querySelector('dialog[open]:not(#management-dialog)')) return null;
        if (selectAccount) {
            selectAccount = false;
            // The account panel owns the live preference values, including pending changes.
            const account = dialog.querySelector('#settings-tab-account:enabled');
            if (account && account.getAttribute('aria-selected') !== 'true') account.click();
        }
        const tab = dialog.querySelector('.settings-tab[aria-selected="true"]');
        const panel = tab && document.getElementById(tab.getAttribute('aria-controls'));
        if (!panel || !panel.getClientRects().length || !dialog.contains(panel)) return null;
        const section = panel.querySelector('.form-section');
        const close = dialog.querySelector('[data-slot="dialog-close"]');
        if (!close) return null;
        const page = {
            overview, identity: accountIdentity(), title: label(tab), section: panel.id, close: controlID(close), theme: root.dataset.theme || 'system',
            sections: Array.from(dialog.querySelectorAll('.settings-tab'), buttonData)
        };
        if (!['settings-panel-general','settings-panel-account','settings-panel-devices'].includes(panel.id) ||
            !section || panel.querySelectorAll('.form-section').length !== 1 || panel.querySelector('input,textarea,select,a[href]')) {
            return {...page, hosted: true, canvas: channels(getComputedStyle(dialog).backgroundColor),
                actions: [], rows: [], alerts: [], picker: null};
        }
        const rows = Array.from(section.querySelectorAll('.form-row:not([hidden])'), row => {
            const controls = row.querySelector('.form-row-controls');
            const texts = Array.from(controls?.children || [])
                .filter(el => !el.matches('button,img') && !el.querySelector('button'))
                .map(label).filter(Boolean);
            const img = controls?.querySelector('img.console-avatar');
            const src = img && URL.canParse(img.src) ? new URL(img.src) : null;
            return {
                id: controlID(row), title: label(row.querySelector('.form-row-label')),
                detail: label(row.querySelector('.form-row-description:not(.form-row-controls *)')),
                values: texts, avatar: src?.protocol === 'https:' && !src.username && !src.password ? src.href : null,
                controls: Array.from(controls?.querySelectorAll('button:not([role=option])') || [], buttonData)
            };
        });
        const trigger = panel.querySelector('button[aria-haspopup=listbox][aria-expanded=true]');
        const list = trigger && document.getElementById(trigger.getAttribute('aria-controls'));
        return {
            ...page, hosted: false,
            actions: Array.from(section.querySelectorAll('.form-section-actions button'), buttonData),
            rows, alerts: Array.from(section.querySelectorAll('[role=alert]')).filter(el => !el.closest('.form-row')).map(label),
            picker: list ? {title: trigger.getAttribute('aria-label') || label(trigger), close: controlID(trigger),
                options: Array.from(list.querySelectorAll('button[role=option]'), buttonData)} : null
        };
    }
    window.consoleSettingsAction = id => {
        const node = actions.get(id);
        if (!(node instanceof HTMLButtonElement) || !node.isConnected || node.disabled ||
            (!node.getClientRects().length && !node.matches('.settings-tab,[data-slot="dialog-close"]')) ||
            !node.closest('#management-dialog[open]') || document.querySelector('dialog[open]:not(#management-dialog)')) return false;
        if (node.matches('.settings-tab')) overview = false;
        node.click();
        scheduleUpdate();
        return true;
    };

    function skillsDialog() {
        if (!mobile.nativeMenu || document.querySelector('dialog[open]:not(#management-dialog, #skill-detail-dialog)')) return null;
        const detail = document.querySelector('#skill-detail-dialog:modal');
        if (detail) return detail;
        const list = document.querySelector('#management-dialog:modal');
        return list?.querySelector('.skills-page')?.getClientRects().length ? list : null;
    }

    function skillsBar(dialog) {
        if (!dialog) return null;
        const close = dialog.querySelector('[data-slot="dialog-close"]');
        const title = label(dialog.querySelector('[data-slot="dialog-title"]'));
        if (!close || !title) return null;
        const detail = dialog.id === 'skill-detail-dialog';
        const refresh = detail ? null : dialog.querySelector('.skills-refresh');
        const tabs = Array.from(dialog.querySelectorAll('.skills-toolbar .skills-tab'));
        if (!detail && (!tabs.some(tab => tab.getAttribute('aria-selected') === 'true') || tabs.some(tab => tab.disabled))) return null;
        return {title, detail, theme: root.dataset.theme || 'system', close: buttonData(close),
            refresh: refresh && buttonData(refresh), tabs: tabs.map(tab => ({
                ...buttonData(tab), label: Array.from(tab.children, label).filter(Boolean).join(' ') || label(tab)
            }))};
    }
    window.consoleSkillsAction = id => {
        const node = actions.get(id);
        const dialog = skillsDialog();
        if (!dialog || !node?.isConnected || node.disabled || !dialog.contains(node) ||
            !node.matches('[data-slot="dialog-close"], .skills-refresh, .skills-toolbar .skills-tab')) return false;
        node.click();
        scheduleUpdate();
        return true;
    };
    return () => {
        updateComposer();
        actions.clear();
        const dialog = skillsDialog();
        const skills = skillsBar(dialog);
        const skillsKey = JSON.stringify(skills);
        if (skillsKey !== lastSkills) {
            lastSkills = skillsKey;
            if (skills) root.dataset.iosSkillsBar = skills.detail ? 'detail' : 'list';
            else delete root.dataset.iosSkillsBar;
            bridge.postMessage({event: 'skills', data: skills});
        }
        const data = settings();
        root.toggleAttribute('data-ios-settings-bar', data?.hosted === true && !data.overview);
        const key = JSON.stringify(data);
        if (key !== lastSettings) {
            lastSettings = key;
            bridge.postMessage({event: 'settings', data});
        }
    };
}

// A Cloud draft stays in the hosted composer until admission. Project the
// locked submission into the transcript without writing to the editor or
// sending a second request. The hosted transcript owns the final bubble.
function installOutgoingPreview() {
    const sendLabels = ['Send', '发送', '傳送', 'Enviar', '送信'];
    function lastUser(stream) {
        const rows = stream.querySelectorAll(':scope > .msg.user');
        return rows.item(rows.length - 1);
    }
    let pending;
    const observer = new MutationObserver(update);

    function clear() {
        observer.disconnect();
        if (!pending) return;
        clearTimeout(pending.unlockCheck);
        pending.stream.removeAttribute('data-ios-outgoing');
        pending.card.removeAttribute('data-ios-sending');
        pending = null;
    }

    function update() {
        if (!pending) return;
        const transcript = document.querySelector('main > #transcript[data-transcript-session]');
        const stream = transcript?.querySelector('#stream');
        const card = document.querySelector('main > .composer .composer-inner');
        const editor = card?.querySelector('#task');
        if (!stream || !editor) return clear();
        const session = transcript.dataset.transcriptSession;
        const send = card.querySelector('#send');
        if (session !== pending.session) {
            // The first send promotes the local draft to a real Cloud session.
            if (!pending.session.startsWith('draft:') || location.pathname !== '/cloud/session/' + session ||
                editor.value !== pending.text || !send?.disabled) return clear();
            pending.session = session;
        }
        const last = lastUser(stream);
        if (last && (last.id || last) !== pending.previous) {
            if (pending.stream.hasAttribute('data-ios-outgoing')) last.setAttribute('data-ios-admitted', '');
            return clear();
        }
        // The run may start and clear the draft before its history arrives.
        // Keep the bubble through that gap. A refusal re-enables the draft.
        if (card.querySelector('#stop') && !editor.value) pending.admitted = true;
        if (send?.disabled || pending.admitted) pending.locked = true;
        else if (pending.locked || !send || editor.value !== pending.text) return clear();
        if (document.querySelector('main .notice.error')) return clear();
        if (pending.stream !== stream) pending.stream.removeAttribute('data-ios-outgoing');
        if (pending.card !== card) pending.card.removeAttribute('data-ios-sending');
        pending.stream = stream;
        pending.card = card;
        if (!stream.hasAttribute('data-ios-outgoing')) {
            stream.dataset.iosOutgoing = pending.label;
            if (document.activeElement === editor) editor.blur();
            transcript.scrollTop = transcript.scrollHeight;
        }
        card.toggleAttribute('data-ios-sending', !pending.admitted && editor.value === pending.text);
    }

    function submitted(card, event) {
        if (!card || card.querySelector('#stop, .shell-mode, .completion-menu')) return;
        const send = card.querySelector('#send:enabled');
        const editor = card.querySelector('#task:enabled');
        const transcript = document.querySelector('main > #transcript[data-transcript-session]');
        const stream = transcript?.querySelector('#stream');
        if (!editor || !stream || !sendLabels.includes(send?.title) || /^\s*\/feedback(?:\s|$)/i.test(editor.value)) return;
        const files = Array.from(card.querySelectorAll('.mention-label, .composer-image img'),
            node => node.alt || node.textContent.trim()).filter(Boolean);
        const label = [...files, editor.value].filter(Boolean).join('\n');
        if (!label.trim()) return;
        if (pending && pending.session === transcript.dataset.transcriptSession && pending.label === label) {
            event.preventDefault();
            event.stopImmediatePropagation();
            return;
        }
        clear();
        const last = lastUser(stream);
        pending = {stream, card, session: transcript.dataset.transcriptSession, previous: last?.id || last,
            text: editor.value, label, locked: false};
        // The hosted renderer schedules its disabled state after the input
        // event. Withdraw an unhandled gesture; an actual send has no timeout.
        pending.unlockCheck = setTimeout(() => { if (!pending?.locked) clear(); }, 1000);
        observer.observe(document.getElementById('app'), {subtree: true, childList: true,
            attributes: true, attributeFilter: ['disabled', 'data-transcript-session']});
        // Let the hosted handler accept the action first, including Enter/IME.
        requestAnimationFrame(update);
    }
    document.addEventListener('click', event => {
        if (event.target.closest?.('aside button, aside a')) clear();
        const send = event.target.closest?.('.composer-actions #send:enabled');
        if (send) submitted(send.closest('.composer-inner'), event);
    }, true);
    document.addEventListener('keydown', event => {
        if (event.key === 'Enter' && !event.shiftKey && !event.isComposing && event.keyCode !== 229 &&
            event.target.matches?.('.composer-inner #task')) submitted(event.target.closest('.composer-inner'), event);
    }, true);
    window.addEventListener('popstate', clear);
    window.addEventListener('pagehide', clear);
}
