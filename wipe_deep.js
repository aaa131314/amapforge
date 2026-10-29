const ACTION = 'deep';
/* wipe_data.js - 删除高德数据（通过 SpringBoard 的 root 权限）
 *
 * 参数通过 send 传入：{ kind:'wipe', deep:bool }
 * 返回：{ kind:'wipe_result', ok, kb, detail }
 */
'use strict';

const TAG = '[wipe]';
const APP_ID = 'com.autonavi.amap';
const DATA_ROOT = '/var/mobile/Containers/Data/Application';

function g(n) {
    try { if (Module.getGlobalExportByName) { var a = Module.getGlobalExportByName(n); if (a) return a; } } catch (e) { }
    try { if (Module.findExportByName) { var b = Module.findExportByName(null, n); if (b) return b; } } catch (e) { }
    return null;
}

function ls(dir) {
    var out = [];
    try {
        var O = new NativeFunction(g('opendir'), 'pointer', ['pointer']);
        var R = new NativeFunction(g('readdir'), 'pointer', ['pointer']);
        var K = new NativeFunction(g('closedir'), 'int', ['pointer']);
        var fd = O(Memory.allocUtf8String(dir));
        if (!fd || fd.isNull()) return out;
        while (true) {
            var e = R(fd);
            if (!e || e.isNull()) break;
            var nl = 0, n = '';
            try { nl = e.add(18).readU16(); } catch (x) { }
            try { n = (nl > 0 && nl < 1024) ? e.add(21).readUtf8String(nl) : e.add(21).readUtf8String(); } catch (x) { continue; }
            if (!n || n === '.' || n === '..') continue;
            out.push(n);
        }
        K(fd);
    } catch (e) { }
    return out;
}

function exists(p) {
    try {
        var S = new NativeFunction(g('stat'), 'int', ['pointer', 'pointer']);
        return S(Memory.allocUtf8String(p), Memory.alloc(256)) === 0;
    } catch (e) { return false; }
}

function findContainer() {
    // 已知容器（优先，沙箱可能禁止列目录）
    var KNOWN = [
        '/var/mobile/Containers/Data/Application/366E1D56-97A4-4613-8351-3C83A47B8F2D'
    ];
    for (var k = 0; k < KNOWN.length; k++) {
        if (exists(KNOWN[k] + '/Library/Preferences/' + APP_ID + '.plist')) return KNOWN[k];
        if (exists(KNOWN[k] + '/Documents')) return KNOWN[k];
    }
    // 遍历兜底
    var tops = ls(DATA_ROOT);
    for (var i = 0; i < tops.length; i++) {
        var cand = DATA_ROOT + '/' + tops[i];
        if (exists(cand + '/Library/Preferences/' + APP_ID + '.plist')) return cand;
    }
    return null;
}

function sizeofDir(p, depth) {
    if (!exists(p)) return 0;
    var total = 0;
    var st = Memory.alloc(512);
    try {
        var S = new NativeFunction(g('stat'), 'int', ['pointer', 'pointer']);
        if (S(Memory.allocUtf8String(p), st) === 0) {
            // st_size at offset 96 on arm64 darwin
            try { total += Number(st.add(96).readU64().toString()); } catch (e) { }
        }
    } catch (e) { }
    if (depth > 0) {
        var kids = ls(p);
        for (var i = 0; i < kids.length && i < 5000; i++) {
            total += sizeofDir(p + '/' + kids[i], depth - 1);
        }
    }
    return total;
}

const STD = [
    'Library/Preferences/com.autonavi.amap.plist',
    'Library/Caches',
    'Documents/feedback',
    'Documents/ajx-biz'
];

const DEEP = [
    'Library/Preferences',
    'Library/Caches',
    'Library/Cookies',
    'Documents',
    'Library/Application Support',
    'Library/WebKit',
    'Library/SplashBoard'
];

function rmrf(path) {
    // 递归删除：先删子项，再 rmdir
    var RMDIR = new NativeFunction(g('rmdir'), 'int', ['pointer']);
    var UNLINK = new NativeFunction(g('unlink'), 'int', ['pointer']);
    var st = Memory.alloc(512);
    var S = new NativeFunction(g('stat'), 'int', ['pointer', 'pointer']);
    var rc = S(Memory.allocUtf8String(path), st);
    if (rc !== 0) return true;  // 不存在，视为成功

    var mode = 0;
    try { mode = st.add(4).readU16() & 0xF000; } catch (e) { }
    var isDir = (mode === 0x4000);

    if (isDir) {
        var kids = ls(path);
        for (var i = 0; i < kids.length; i++) {
            rmrf(path + '/' + kids[i]);
        }
        return RMDIR(Memory.allocUtf8String(path)) === 0;
    } else {
        return UNLINK(Memory.allocUtf8String(path)) === 0;
    }
}

function doWipe(deep) {
    var out = { ok: false, kb: 0, detail: '' };
    var D = findContainer();
    if (!D) {
        out.detail = 'container not found';
        send({ kind: 'wipe_result', ok: false, kb: 0, detail: out.detail });
        return;
    }
    var targets = deep ? DEEP : STD;
    var lines = ['container: ' + D, deep ? 'mode: DEEP' : 'mode: STANDARD'];
    var totalKb = 0;

    for (var i = 0; i < targets.length; i++) {
        var t = targets[i];
        var full = D + '/' + t;
        if (!exists(full)) { lines.push('  skip  ' + t + ' (absent)'); continue; }
        var bytes = sizeofDir(full, 6);
        var kb = Math.round(bytes / 1024);
        var ok = rmrf(full);
        if (ok && !exists(full)) {
            totalKb += kb;
            lines.push('  OK    ' + t + '  (-' + kb + 'KB)');
        } else {
            lines.push('  FAIL  ' + t);
        }
    }

    lines.push('');
    lines.push('cleaned: ' + totalKb + 'KB');
    lines.push('next launch regenerates diu / adiu / caches');

    send({ kind: 'wipe_result', ok: true, kb: totalKb, detail: lines.join('\n') });
}

function doSize() {
    var D = findContainer();
    if (!D) { send({ kind: 'size_result', ok: false }); return; }
    var bytes = sizeofDir(D, 7);
    var mb = bytes / 1024 / 1024;
    send({ kind: 'size_result', ok: true, path: D,
           human: (mb >= 1 ? mb.toFixed(1) + ' MB' : Math.round(bytes / 1024) + ' KB') });
}

// 挂上 ntfy 消息处理
function boot() {
    if (typeof ObjC === 'undefined') { setTimeout(boot, 300); return; }
    console.log(TAG + ' ready');
    send({ kind: 'wipe_ready', ts: Date.now() });
}

// CLI 模式：按脚本内容里的 ACTION 常量决定行为
function boot2() {
    if (typeof ObjC === 'undefined') { setTimeout(boot2, 300); return; }
    console.log(TAG + ' ready, action=' + ACTION);
    send({ kind: 'wipe_ready', ts: Date.now() });
    if (ACTION === 'size') {
        doSize();
    } else {
        doWipe(ACTION === 'deep');
    }
}
boot2();
