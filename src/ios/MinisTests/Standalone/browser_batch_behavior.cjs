
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const {test} = require('node:test');

const source = fs.readFileSync(process.argv[2], 'utf8');
const script = source.match(/static let batchRuntime = #"""\r?\n([\s\S]*?)\r?\n\s*"""#/);
// Render just the batch-mode interpolations in the shipping click template.
// This exercises the emitted event chain even when swiftc is unavailable.
const clickSource = source.split('    static func click(selector:')[1]?.split('    static func clickCoordinate(')[0];
const clickTemplate = clickSource?.match(/"""\r?\n([\s\S]*?)\r?\n\s*"""/)?.[1];
const guardTemplate = source.match(/return "(if \(![^\n]*interrupted: true[^\n]*)"/)?.[1];
const cleanupTemplate = clickSource?.match(/guardName\.map \{ "([^"\n]+)" \}/)?.[1];
function clickAction(context) {
    assert.ok(clickTemplate, 'shared click template missing');
    const guard = guardTemplate?.replace('\\(guardName)', 'allowed') ?? '';
    const cleanup = cleanupTemplate?.replace('\\($0)', 'allowed') ?? '';
    const body = clickTemplate.replace(/\\\(target.*\);/, 'node;')
        .replaceAll('\\(jsQuote(selector))', '')
        .replaceAll('\\(actionCheck)', guard)
        .replaceAll('\\(cleanupCheck)', cleanup);
    assert.ok(!body.includes('\\('), 'click fixture did not resolve Swift interpolations');
    return vm.runInContext('(node, allowed) => ' + body, context);
}

const typeTemplate = source.split('    static func type(selector:')[1]?.match(/"""\r?\n([\s\S]*?)\r?\n\s*"""/)?.[1];
function typeAction(context) {
    assert.ok(typeTemplate, 'shared type template missing');
    const guard = guardTemplate?.replace('\\(guardName)', 'allowed') ?? '';
    const body = typeTemplate.replace(/\\\(target.*\);/, 'node;')
        .replaceAll('\\(jsQuote(selector))', '')
        .replaceAll('\\(typedValue)', 'value')
        .replaceAll('\\(actionCheck)', guard)
        .replaceAll('\\(isBatch)', 'true')
        .replaceAll('\\(canFinish)', 'allowed()');
    assert.ok(!body.includes('\\('), 'type fixture did not resolve Swift interpolations');
    return vm.runInContext('(node, allowed, value) => ' + body, context);
}

class FixtureEvent { constructor(type, options) { this.type = type; Object.assign(this, options); } }
class FixtureInput {
    get value() { return this.currentValue; }
    set value(value) { this.currentValue = value; }
}


function fixture() {
    const nodes = [];
    const observers = new Set();
    const events = new Map();
    let modal = [];
    const location = {href: 'https://example.test/'};
    let now = Date.now();
    const document = {
        title: 'Fixture', readyState: 'complete', documentElement: {}, activeElement: null,
        querySelectorAll(selector) {
            if (selector.startsWith('dialog[')) return modal;
            if (selector === 'iframe,frame') return [];
            if (selector === '!') throw new SyntaxError();
            return nodes.filter(node => node.isConnected && node.selector === selector);
        },
        querySelector(selector) { return this.querySelectorAll(selector)[0] ?? null; },
        addEventListener(name, fn) { events.set(name, fn); },
        removeEventListener(name, fn) { if (events.get(name) === fn) events.delete(name); },
        createTreeWalker(root) {
            let index = 0;
            return {nextNode: () => root.textNodes?.[index++] ?? null};
        },
    };
    document.body = {
        querySelectorAll: () => nodes.filter(node => node.isConnected),
        matches: () => false,
    };
    const context = vm.createContext({
        document, location, URL, Date: {now: () => now}, setTimeout, clearTimeout, NodeFilter: {SHOW_TEXT: 4},
        getComputedStyle: () => ({visibility: 'visible'}),
        window: {},
        MouseEvent: FixtureEvent, KeyboardEvent: FixtureEvent, InputEvent: FixtureEvent,
        Event: FixtureEvent, FocusEvent: FixtureEvent,
        HTMLInputElement: FixtureInput, HTMLTextAreaElement: FixtureInput,
        MutationObserver: class {
            constructor(cb) { this.cb = cb; }
            observe() { observers.add(this); }
            disconnect() { observers.delete(this); }
        },
    });
    function notify() { for (const item of [...observers]) item.cb(); }
    function node(selector, onClick = () => {}) {
        const item = {
            selector, isConnected: true, ownerDocument: document, tagName: 'BUTTON',
            disabled: false, clicks: 0, innerText: selector,
            matches: () => false, closest: () => null, getClientRects: () => [1],
            getAttribute: () => null, hasAttribute: () => false,
            dispatchEvent(event) { if (event.type === 'mousedown') this.onBeforeClick?.(); },
            click() { this.clicks++; onClick(); },
        };
        nodes.push(item);
        return item;
    }
    function input(selector, onEvent = () => {}) {
        const item = Object.assign(new FixtureInput(), node(selector), {
            tagName: 'INPUT', value: 'old query', realBlurs: 0, events: [],
            matches: query => query.startsWith('textarea,input:'),
            focus() { document.activeElement = this; },
            blur() {
                assert.equal(document.activeElement, this, 'only the focused input can be blurred');
                document.activeElement = null;
                this.realBlurs++;
                this.dispatchEvent(new FixtureEvent('blur'));
                this.dispatchEvent(new FixtureEvent('focusout'));
            },
            dispatchEvent(event) { this.events.push(event.type); onEvent(event, this); },
        });
        nodes[nodes.length - 1] = item;
        return item;
    }
    async function command(kind, args = {}, epoch = '0') {
        assert.ok(script, 'observe/run must provide a browser runtime');
        if (!context.__minisBrowserBatch) {
            vm.runInContext(script[1], context);
        }
        return JSON.parse(JSON.stringify(await context.__minisBrowserBatch.command(kind, epoch, {
            deadline: now + 350, runId: 'run-a', ...args,
        }, {
            click: clickAction(context),
            type: typeAction(context),
        })));
    }
    return {node, input, command, notify, observers, location, advance: ms => { now += ms; }, event: (name, event) => events.get(name)?.(event), openModal: node => { modal = [node]; }};
}

async function observe(f) {
    const result = await f.command('observe', {version: 'doc-a'});
    assert.equal(result.status, 'ok');
    assert.equal((await f.command('begin', {version: result.observation.documentVersion})).status, 'ok');
    return result.observation;
}
function action(observation, index = 0, condition = undefined) {
    return {version: observation.documentVersion, ref: observation.elements[index].ref, action: 'click', condition};
}
test('registers the goal before clicking and checks it immediately after dispatch', async () => {
    const f = fixture();
    const button = f.node('#submit', () => {
        assert.equal(f.observers.size, 1);
        f.node('#done');
    });
    const observation = await observe(f);
    const result = await f.command('step', action(observation, 0, {kind: 'visible', selector: '#done'}));
    assert.deepEqual(result, {status: 'ok', applied: true});
    assert.equal(button.clicks, 1);
    assert.equal(f.observers.size, 0);
});
test('wakes when the goal appears after dispatch', async () => {
    const f = fixture();
    f.node('#submit');
    const observation = await observe(f);
    const args = action(observation, 0, {kind: 'enabled', selector: '#done'});
    assert.deepEqual(await f.command('step', args), {status: 'waiting', applied: true});
    const pending = f.command('wait', {version: observation.documentVersion});
    setTimeout(() => { f.node('#done'); f.notify(); }, 5);
    assert.equal((await pending).status, 'ok');
});
test('does not redirect a stale ref to a replacement with the same selector', async () => {
    const f = fixture();
    const original = f.node('#same');
    const observation = await observe(f);
    original.isConnected = false;
    const replacement = f.node('#same');
    assert.equal((await f.command('step', action(observation))).status, 'stale_ref');
    assert.equal(replacement.clicks, 0);
});
test('rejects an ambiguous condition before dispatch', async () => {
    const f = fixture();
    const button = f.node('#submit');
    f.node('#duplicate');
    f.node('#duplicate');
    const observation = await observe(f);
    const result = await f.command('step', action(observation, 0, {kind: 'visible', selector: '#duplicate'}));
    assert.equal(result.status, 'ambiguous_condition');
    assert.equal(button.clicks, 0);
});
test('reports an applied step which opened a dialog', async () => {
    const f = fixture();
    f.node('#open', () => f.openModal(f.node('#dialog')));
    const next = f.node('#next');
    const observation = await observe(f);
    assert.deepEqual(await f.command('step', action(observation)), {status: 'dialog', applied: true});
    assert.equal(next.clicks, 0);
});
test('old references cannot dispatch after the native context changes', async () => {
    const f = fixture();
    const button = f.node('#submit');
    const observation = await observe(f);
    assert.equal((await f.command('step', action(observation), '1')).status, 'stale_document');
    assert.equal(button.clicks, 0);
});


test('stops after a link dispatch before waiting for a WebKit navigation callback', async () => {
    const f = fixture();
    const link = {
        href: 'https://example.test/next', target: '', hasAttribute: () => false,
    };
    f.node('#link', () => f.event('click', {target: {closest: () => link}, defaultPrevented: false}));
    const observation = await observe(f);
    assert.deepEqual(await f.command('step', action(observation)), {status: 'navigation', applied: true});
});
test('permits a page handler to cancel the link default action for an SPA transition', async () => {
    const f = fixture();
    const link = {href: 'https://example.test/next', target: '', hasAttribute: () => false};
    f.node('#spa', () => {
        const event = {target: {closest: () => link}, defaultPrevented: false};
        f.event('click', event);
        event.defaultPrevented = true;
        f.location.href = link.href;
    });
    const observation = await observe(f);
    const result = await f.command('step', action(observation, 0, {kind: 'url_contains', value: '/next'}));
    assert.deepEqual(result, {status: 'ok', applied: true});
});

test('does not dispatch an action if its bridge arrived after the deadline', async () => {
    const f = fixture();
    const button = f.node('#submit');
    const observation = await observe(f);
    const result = await f.command('step', {...action(observation), deadline: 0});
    assert.equal(result.status, 'timeout');
    assert.equal(button.clicks, 0);
});
test('does not treat an earlier condition as a substitute for a final goal', async () => {
    const f = fixture();
    f.node('#submit', () => f.node('#enabled'));
    const observation = await observe(f);
    const result = await f.command('step', {
        ...action(observation, 0, {kind: 'enabled', selector: '#enabled'}),
        goal: {kind: 'visible', selector: '#done'},
    });
    assert.deepEqual(result, {status: 'waiting', applied: true});
    const waiting = f.command('wait', {version: observation.documentVersion});
    f.node('#done');
    f.notify();
    assert.equal((await waiting).status, 'ok');
});

test('rechecks the deadline after target resolution and before the first event', async () => {
    const f = fixture();
    const button = f.node('#submit');
    const observation = await observe(f);
    button.getClientRects = () => { f.advance(400); return [1]; };
    assert.equal((await f.command('step', action(observation))).status, 'timeout');
    assert.equal(button.clicks, 0);
});
test('stops the click chain if a synchronous event listener consumes its budget', async () => {
    const f = fixture();
    const button = f.node('#submit');
    const observation = await observe(f);
    button.onBeforeClick = () => f.advance(400);
    assert.equal((await f.command('step', action(observation))).status, 'dispatch_unconfirmed');
    assert.equal(button.clicks, 0);
});
test('does not expose a descendant editable value in an outer interactive label', async () => {
    const f = fixture();
    const wrapper = f.node('#wrapper');
    wrapper.innerText = 'Menu confidential input';
    wrapper.textNodes = [
        {parentElement: wrapper, nodeValue: 'Menu'},
        {parentElement: {closest: selector => selector.includes('[contenteditable]') ? wrapper : null,
                         getClientRects: () => [1]}, nodeValue: 'confidential input'},
    ];
    const observation = await observe(f);
    assert.equal(observation.elements[0].name, 'Menu');
    assert.ok(!JSON.stringify(observation).includes('confidential input'));
});

test('reports the main click even if its handler removes the clicked element', async () => {
    const f = fixture();
    const button = f.node('#search', () => {
        button.isConnected = false;
        f.node('#result');
    });
    const observation = await observe(f);
    assert.deepEqual(await f.command('step', action(observation, 0, {kind: 'visible', selector: '#result'})),
        {status: 'ok', applied: true});
    assert.equal(button.clicks, 1);
});

test('preserves a confirmed click when its main listener uses the rest of the budget', async () => {
    const f = fixture();
    const button = f.node('#search', () => f.advance(400));
    const observation = await observe(f);
    assert.deepEqual(await f.command('step', action(observation)), {status: 'timeout', applied: true});
    assert.equal(button.clicks, 1);
});

test('empty type updates input-driven state before the next submit', async () => {
    const f = fixture();
    let appValue = 'old query', submitted;
    const input = f.input('#query', (event, node) => { if (event.type === 'input') appValue = node.value; });
    f.node('#submit', () => { submitted = appValue; });
    const observed = await observe(f);
    assert.deepEqual(await f.command('step', {...action(observed), action: 'type', text: ''}), {status: 'ok', applied: true});
    assert.deepEqual(await f.command('step', action(observed, 1)), {status: 'ok', applied: true});
    assert.equal(input.value, '');
    assert.equal(submitted, '');
    assert.deepEqual(input.events.filter(name => name === 'input'), ['input']);
});

test('batch type blurs its focused input once without synthetic duplicates', async () => {
    const f = fixture();
    const input = f.input('#query');
    const observed = await observe(f);
    assert.deepEqual(await f.command('step', {...action(observed), action: 'type', text: 'new'}), {status: 'ok', applied: true});
    assert.equal(input.value, 'new');
    assert.equal(input.events.filter(name => name === 'input').length, 3);
    assert.equal(input.realBlurs, 1);
    assert.deepEqual(input.events.filter(name => name === 'blur' || name === 'focusout'), ['blur', 'focusout']);
});

test('batch type does not blur any input after a change listener uses the deadline', async () => {
    const f = fixture();
    const input = f.input('#query', event => { if (event.type === 'change') f.advance(351); });
    const observed = await observe(f);
    assert.deepEqual(await f.command('step', {...action(observed), action: 'type', text: 'new'}), {status: 'timeout', applied: true});
    assert.equal(input.value, 'new');
    assert.equal(input.realBlurs, 0);
    assert.ok(!input.events.includes('blur'));
});

test('batch type leaves focus alone when a change listener moves it', async () => {
    const f = fixture();
    const next = f.input('#next');
    const input = f.input('#query', event => { if (event.type === 'change') next.focus(); });
    const observed = await observe(f);
    assert.deepEqual(await f.command('step', {...action(observed, 1), action: 'type', text: 'new'}), {status: 'ok', applied: true});
    assert.equal(next.realBlurs, 0);
    assert.ok(!input.events.includes('blur'));
});

test('empty batch type cannot clear a password through the regular type action', async () => {
    const f = fixture();
    const input = f.input('#secret');
    input.matches = query => query.startsWith('input[type="password"]');
    const observed = await observe(f);
    assert.deepEqual(await f.command('step', {...action(observed), action: 'type', text: ''}), {status: 'secure_input_required'});
    assert.equal(input.value, 'old query');
    assert.deepEqual(input.events, []);
});
