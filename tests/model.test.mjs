import test from 'node:test';import assert from 'node:assert/strict';
import {mean,validate,snapshot,shareHTML,escapeHTML} from '../docs/model.js';
const visit={id:'v1',placeKey:'branch1',name:'店铺 <script>',address:'测试地址',category:'咖啡',arrived:'2026-10-06T03:00:00Z',departed:null,rating:4.5,note:'<script>alert(1)</script>',location:{lat:31,lng:121},photos:[]};
test('unrated is excluded from mean',()=>assert.equal(mean([{rating:null},{rating:4.5},{rating:3.5}]),4));
test('half-star and time validation',()=>{assert.doesNotThrow(()=>validate(visit));assert.throws(()=>validate({...visit,rating:4.2}));assert.throws(()=>validate({...visit,departed:'2026-10-05T00:00:00Z'}))});
test('snapshot omits private coordinates and exact time',()=>{const s=snapshot(visit,'s1');assert.equal(s.date,'2026-10-06');assert.equal(s.location,undefined);assert.equal(s.arrived,undefined);visit.note='已修改';assert.notEqual(s.note,visit.note)});
test('export escapes user text and rejects untrusted photo URLs',()=>{const s=snapshot({...visit,note:'<script>bad()</script>',photos:[{data:'javascript:alert(1)'}]},'s1');const html=shareHTML({title:'<img onerror=x>',items:[s]});assert(!html.includes('<script>'));assert(!html.includes('javascript:'));assert(html.includes('&lt;script&gt;'));assert.equal(escapeHTML('"<&'), '&quot;&lt;&amp;')});
