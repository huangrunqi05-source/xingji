"""Run only against the local built Worker. Uses disposable test identities."""
import json,uuid,urllib.request,urllib.error,struct
from pathlib import Path
BASE='http://127.0.0.1:8787'
checks=[]
def call(path='/api/diary',data=None,user='xingji-test-a',method=None,raw=False):
    headers={}
    if user: headers.update({'oai-authenticated-user-id':user,'oai-authenticated-user-email':user+'@example.test'})
    if data is not None and not raw: data=json.dumps(data,ensure_ascii=False).encode();headers['Content-Type']='application/json'
    req=urllib.request.Request(BASE+path,data=data,headers=headers,method=method)
    try:r=urllib.request.urlopen(req);body=r.read();return r.status,body if raw else json.loads(body)
    except urllib.error.HTTPError as e:return e.code,e.read()
def ok(value,label):
    assert value,label
    checks.append(label)
def post(action,**kw):return call(data={'action':action,**kw})
uid=lambda:str(uuid.uuid4())
v={'id':uid(),'placeKey':'qa:branch-1','name':'测试咖啡（甲分店）','address':'测试地址','category':'咖啡','arrived':'2026-10-06T03:00:00.000Z','departed':None,'rating':4.5,'note':'<script>不可作为 HTML 执行</script>','location':{'lat':31.2,'lng':121.5,'system':'WGS84','source':'browser','accuracy':20}}
ok(call(user=None)[0]==401,'anonymous cannot read diary')
ok(post('saveVisit',visit=v)[0]==200,'save visit and half-star rating')
ok(post('saveVisit',visit=v)[0]==200,'idempotent visit retry')
ok(len(call()[1]['visits'])==1,'retry does not duplicate visits')
ok(post('saveVisit',visit={**v,'rating':4.2})[0]==400,'reject invalid rating increments')
ok(post('saveVisit',visit={**v,'departed':'2026-10-05T03:00:00.000Z'})[0]==400,'reject inverted visit times')
ok(call(user='xingji-test-b')[1]['visits']==[],'other user cannot list visits')
ok(call(data={'action':'saveVisit','visit':v},user='xingji-test-b')[0]==403,'other user cannot overwrite a known visit')
pid=uid();jpeg=Path('public/coffee.jpg').read_bytes();meta=b'Exif\x00\x00GPS PRIVATE TEST';injected=jpeg[:2]+b'\xff\xe1'+struct.pack('>H',len(meta)+2)+meta+jpeg[2:]
ok(call('/api/photos/'+pid+'?visit='+v['id'],injected,method='PUT',raw=True)[0]==200,'photo stored in local R2')
status,photo=call('/api/photos/'+pid,raw=True)
ok(status==200 and b'GPS PRIVATE TEST' not in photo,'uploaded photo strips GPS metadata')
ok(call('/api/photos/'+pid,user='xingji-test-b',raw=True)[0]==404,'photo ownership enforced')
lid=uid();item=uid()
ok(post('createList',id=lid,title='测试清单')[0]==200,'create list')
ok(post('addToList',id=item,listId=lid,visitId=v['id'])[0]==200,'snapshot copies record and photo')
snapshot=call()[1]['lists'][0]['items'][0]
ok('location' not in snapshot and 'arrived' not in snapshot and snapshot['date']=='2026-10-06','snapshot excludes coordinates and precise time')
post('saveVisit',visit={**v,'note':'私人修改'})
ok(call()[1]['lists'][0]['items'][0]['note']==v['note'],'private edit does not mutate shared snapshot')
ok(post('deleteVisit',id=v['id'])[0]==200,'delete original visit')
ok(call('/api/photos/'+pid,raw=True)[0]==404,'original photo removed')
ok(call('/api/photos/'+snapshot['photoIds'][0],raw=True)[0]==200,'snapshot photo survives original deletion')
ok(call('/api/photos/'+snapshot['photoIds'][0],user='xingji-test-b',raw=True)[0]==404,'snapshot photo ownership enforced')
ok(post('deleteList',id=lid)[0]==200,'delete list')
ok(call('/api/photos/'+snapshot['photoIds'][0],raw=True)[0]==404,'deleted snapshot photo unavailable')
ok(call()[1]=={'visits':[],'lists':[]},'test identity cleaned up')
print('\n'.join('PASS '+x for x in checks));print(f'{len(checks)} checks passed')
