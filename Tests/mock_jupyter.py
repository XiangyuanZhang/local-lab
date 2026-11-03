import asyncio,json,sys,copy,os
from aiohttp import web
existing=[{'id':'existing-one','name':'python3'},{'id':'existing-two','name':'python3'}]
created=False
app=web.Application()
def authorized(r):return r.headers.get('Authorization')=='token integration-test-only'
async def kernels(r):
 global created,files
 if not authorized(r):return web.json_response({'message':'Forbidden'},status=403)
 if r.method=='GET':return web.json_response(existing+([{'id':'app-owned','name':'python3'}] if created else []))
 created=True;files=copy.deepcopy(INITIAL_FILES);return web.json_response({'id':'app-owned','name':'python3'},status=201)
async def specs(r):return web.json_response({'kernelspecs':{'python3':{'spec':{'language':'python','display_name':'Python 3'}}}})
async def kernel(r):
 global created
 if r.match_info['id']!='app-owned':return web.json_response({'error':'Existing kernel touched!'},status=500)
 if r.method=='DELETE':created=False;return web.Response(status=204)
 return web.json_response({'id':'app-owned','name':'python3'},status=200) if created else web.json_response({'message':'Not found'},status=404)
async def interrupt(r):return web.Response(status=204)
async def channels(r):
 ws=web.WebSocketResponse();await ws.prepare(r)
 async for raw in ws:
  msg=json.loads(raw.data);mid=msg['header']['msg_id'];kind=msg['header']['msg_type']
  async def send(kind,content,parent=mid):await ws.send_json({'header':{'msg_type':kind},'parent_header':{'msg_id':parent},'content':content})
  if kind=='kernel_info_request':await send('kernel_info_reply',{'status':'ok','language_info':{'version':'3.10.12'}})
  elif kind=='execute_request':
   await send('stream',{'name':'stdout','text':'WRONG PARENT MUST BE IGNORED\n'},parent='other-session')
   await send('status',{'execution_state':'busy'})
   await send('stream',{'name':'stdout','text':'Hello from local API\n'})
   await send('execute_reply',{'status':'ok'})
   await send('status',{'execution_state':'idle'})
 return ws
INITIAL_FILES={
 'Lecture.ipynb':{'type':'notebook','content':{'nbformat':4,'nbformat_minor':5,'metadata':{},'cells':[{'cell_type':'markdown','source':['# Notebook in App\n'],'metadata':{}},{'cell_type':'code','source':['print(42)\n'],'metadata':{},'execution_count':1,'outputs':[{'output_type':'stream','name':'stdout','text':['42\n']}]}]}},
 'Notes.md':{'type':'file','content':'original remote text'},
 'datasets':{'type':'directory'},
 'datasets/data.py':{'type':'file','content':'print(7)\n'}
}
files=copy.deepcopy(INITIAL_FILES)
def filemodel(path,content=True):
 v=files.get(path, {'type':'directory'})
 kind=v['type']
 result={'name':path.split('/')[-1], 'path':path, 'type':kind, 'writable':True, 'last_modified':'2026-10-13T08:00:00.000Z', 'size':len(v.get('content','').encode()) if kind=='file' else None, 'format':'text' if kind=='file' else 'json'}
 if kind=='directory':result['content']=[filemodel(k,False) for k in files if (k.rsplit('/',1)[0] if '/' in k else '')==path]
 else:result['content']=v.get('content') if content else None
 return result
async def contents(r):
 if not authorized(r):return web.json_response({'message':'Forbidden'},status=403)
 path=r.match_info.get('path','')
 if r.method=='GET':
  if path and path not in files:return web.json_response({'message':'Not found'},status=404)
  return web.json_response(filemodel(path,r.query.get('content')!='0'))
 if r.method=='DELETE':
  if path not in files:return web.Response(status=404)
  del files[path];return web.Response(status=204)
 if r.method=='PUT':
  payload=await r.json();was_present=path in files
  files[path]={'type':payload.get('type','file'),'content':payload.get('content','')}
  return web.json_response(filemodel(path),status=200 if was_present else 201)
 return web.Response(status=405)
app.router.add_route('*','/api/contents/{path:.*}',contents)
app.router.add_route('*','/api/kernels',kernels)
app.router.add_get('/api/kernelspecs',specs)
app.router.add_route('*','/api/kernels/{id}',kernel)
app.router.add_post('/api/kernels/{id}/interrupt',interrupt)
app.router.add_get('/api/kernels/{id}/channels',channels)
port=int(os.environ.get('LOCAL_LAB_TEST_MOCK_PORT','18768'))
web.run_app(app,host='127.0.0.1',port=port,print=lambda x: print(f'Mock ready: 127.0.0.1:{port}',flush=True),access_log=None)
