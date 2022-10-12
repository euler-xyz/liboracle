const fs = require('fs');

const windowLen = 1800;


let data = [];

{
    let lines = fs.readFileSync(0, 'utf-8').split('\n');

    for (let l of lines) {
        l = l.trim();
        if (!l.startsWith("DATA")) continue;
        rec = {};
        [_, rec.duration, rec.newTick, rec.actualAge, rec.median, rec.average] = l.split(',').map(n => parseInt(n));
        data.push(rec);
    }
}


let updates = [];
let seen = 0, seenFullWindow = 0;
let seenDupTicks = 0;
let seenZeroDuration = 0;
let prevTick;

for (let d of data) {
    updates.push(d);

    let arr = [];

    for (let i = updates.length - 1; i >= 0; i--) {
        for (let j = 0; j < updates[i].duration; j++) {
            arr.push(updates[i].newTick);
            if (arr.length === d.actualAge) break;
        }
        if (arr.length === d.actualAge) break;
    }

    arr.sort((a,b) => Math.sign(a-b));

    let median = downscaleTick(arr[Math.trunc((d.actualAge + 1) / 2) - 1]) * 256;
    let average = Math.trunc(arr.map(a => downscaleTick(a) * 256).reduce((a,b) => a + b) / d.actualAge);

    if (process.env.VERBOSE) {
        console.log("------------");
        console.log("RAW", d);
        console.log("MEDIAN=",median);
        console.log("AVERAGE=",average);
        console.log("ACTUALAGE=",arr.length);
    }

    if (d.median !== median) throw(`DIFFERENT MEDIAN ${d.median} / ${median}`);
    if (d.average !== average) throw(`DIFFERENT AVERAGE ${d.average} / ${average}`);

    seen++;
    if (d.actualAge === windowLen) {
        seenFullWindow++;
    }

    if (prevTick === d.newTick) seenDupTicks++;

    if (prevTick !== d.newTick && d.duration === 0) seenZeroDuration++;

    prevTick = d.newTick;
}

console.log(`${seen} total, ${seenFullWindow} full window, ${seenDupTicks} dup ticks, ${seenZeroDuration} zero durations`);

if (seen === 0) throw(`no ticks seen`);
if (seenFullWindow === 0) throw(`no full windows seen`);
if (seenDupTicks === 0) throw(`no dup ticks seen`);
if (seenZeroDuration === 0) throw(`no zero durations seen`);


function downscaleTick(t) {
    return Math.trunc((t + (t > 0 ? 128 : -128)) / 256);
}
