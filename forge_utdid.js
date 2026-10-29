/* forge_utdid.js - 只 hook +[UTDevice utdid]，返回随机设备 ID。
 * 严格排除 + initialize（返回 void，hook 会崩）。
 */
'use strict';

const TAG = '[forge]';
let CUR = null;
let N = 0;

function randTid() {
    const cs = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    let s = '';
    for (let i = 0; i < 22; i++) s += cs.charAt(Math.floor(Math.random() * cs.length));
    return s;
}

function nsstr(s) {
    return ObjC.classes.NSString.stringWithString_(s);
}

function boot() {
    if (typeof ObjC === 'undefined') { setTimeout(boot, 150); return; }
    CUR = randTid();
    console.log(TAG + ' forged UTDID=' + CUR);

    try {
        const UTD = ObjC.classes.UTDevice;
        if (!UTD) { console.log(TAG + ' UTDevice absent'); return; }

        // 只挂 + utdid —— 唯一返回设备 ID 且返回 NSString 的方法
        const m = UTD['+ utdid'];
        if (!m) { console.log(TAG + ' + utdid absent'); return; }

        Interceptor.attach(m.implementation, {
            onLeave: function (ret) {
                try {
                    N++;
                    if (!ret || ret.isNull()) return;
                    // 用 replace 换掉返回值
                    ret.replace(nsstr(CUR));
                    if (N <= 20) send({ kind: 'served', n: N, utdid: CUR, ts: Date.now() });
                } catch (e) {
                    if (N <= 5) send({ kind: 'err', msg: String(e), ts: Date.now() });
                }
            }
        });
        console.log(TAG + ' hooked +[UTDevice utdid]');
        send({ kind: 'ready', utdid: CUR });
    } catch (e) {
        console.log(TAG + ' boot err: ' + e);
    }
}

try { boot(); } catch (e) { console.log(TAG + ' top: ' + e); }

setTimeout(function () {
    try {
        if (typeof ObjC === 'undefined') return;
        send({ kind: 'stat', served: N, utdid: CUR });
    } catch (e) { }
}, 15000);
