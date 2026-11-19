from pathlib import Path
from collections import deque
import ast,copy,json,csv,math,hashlib,shutil,zipfile
import numpy as np
from PIL import Image,ImageFilter,ImageDraw
ROOT=Path(__file__).resolve().parent
BASE=ROOT.parent/'batch09_visibility_tiles'
src=Image.open(ROOT/'source.png')
assert src.size==(3840,2160),('STOP_NON_4K',src.size)
src=src.convert('RGBA')
tree=ast.parse((ROOT.parent/'batch01_v3_final/process.py').read_text(encoding='utf-8'))
exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef)],type_ignores=[]),'alpha_helpers','exec'))
tree=ast.parse((ROOT.parent/'batch05_repairs_extend/process.py').read_text(encoding='utf-8'))
nodes=[copy.deepcopy(n) for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in ('multi_core','clean_packaging')]
for fn in nodes:
    if fn.name=='clean_packaging':
        fn.name='clean_asset'
        for n in ast.walk(fn):
            if isinstance(n,ast.Name) and n.id=='largest':n.id='multi_core'
exec(compile(ast.fix_missing_locations(ast.Module(body=nodes,type_ignores=[])),'multi_component_alpha','exec'))
tree=ast.parse((BASE/'process.py').read_text(encoding='utf-8'))
exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='resize_actual'],type_ignores=[]),'bbox_rounding','exec'))
old=json.loads((BASE/'manifest.json').read_text(encoding='utf-8'))
m=copy.deepcopy(old)
atlases=[Image.open(BASE/f'atlas_{i}_3840x2160.png').convert('RGBA') for i in (1,2)]
before=[np.array(a) for a in atlases]
allowed=np.zeros((2160,3840),bool)
(ROOT/'individual').mkdir(exist_ok=True)
for r in m['items']:
    shutil.copy2(BASE/r['file'],ROOT/r['file'])
    r['source_baseline']=str(BASE)
    r['operation']='byte_identical_reuse'
changed=[3,15]
crops={3:[0,0,2600,2000],15:[2650,0,3840,2160]}
for k in changed:
    r=m['items'][k-1]
    raw=src.crop(crops[k]);im=clean_asset(raw)
    # Hold display limits and cell allocation; preserve corrected native proportions.
    limit=(432,240) if k==3 else (164,240)
    factor=min(limit[0]/im.width,limit[1]/im.height)
    im,delta=resize_actual(im,[im.width*factor,im.height*factor])
    assert [math.ceil(im.width/256),math.ceil(im.height/256)]==[r['grid_cols'],r['grid_rows']]
    oldbox=(r['sheet_x'],r['sheet_y'],r['sheet_right'],r['sheet_bottom'])
    atlas=atlases[r['atlas']-1];atlas.paste((0,0,0,0),oldbox)
    allowed[oldbox[1]:oldbox[3],oldbox[0]:oldbox[2]]=True
    x=r['grid_x']*256+(r['grid_cols']*256-im.width)//2
    y=r['grid_y']*256+(r['grid_rows']*256-im.height)//2
    atlas.paste(im,(x,y));allowed[y:y+im.height,x:x+im.width]=True
    out=Image.new('RGBA',(im.width+48,im.height+48));out.paste(im,(24,24));out.save(ROOT/r['file'])
    r.update(operation='targeted_redraw',bbox_width=im.width,bbox_height=im.height,sheet_x=x,sheet_y=y,sheet_right=x+im.width,sheet_bottom=y+im.height,padding=24,rounding_delta_px=delta,source_file='source.png',source_crop=crops[k],native_source=dict(source_path=str(ROOT/'source.png'),source_crop=crops[k]),baseline_file=str(BASE/r['file']))
for i,a in enumerate(atlases,1):
    if i==2:shutil.copy2(BASE/f'atlas_{i}_3840x2160.png',ROOT/f'atlas_{i}_3840x2160.png')
    else:a.save(ROOT/f'atlas_{i}_3840x2160.png')
    for theme,color in [('light',(236,239,243)),('dark',(28,33,43))]:
        bg=Image.new('RGBA',a.size,color+(255,));bg.alpha_composite(a);bg.convert('RGB').save(ROOT/f'preview_{i}_{theme}.png')
        grid=bg.copy();d=ImageDraw.Draw(grid)
        for xx in range(0,3841,256):d.line((xx,0,xx,2048),fill=(145,155,165))
        for yy in range(0,2049,256):d.line((0,yy,3840,yy),fill=(145,155,165))
        for r in m['items']:
            if r['atlas']!=i:continue
            b=(r['grid_x']*256,r['grid_y']*256,(r['grid_x']+r['grid_cols'])*256-1,(r['grid_y']+r['grid_rows'])*256-1)
            d.rectangle(b,outline=(35,160,95),width=2);d.text((b[0]+4,b[1]+4),f"{r['id']:02d} {r['grid_cols']}x{r['grid_rows']}={r['total_cells']}",fill=(35,160,95))
        grid.convert('RGB').save(ROOT/f'grid_{i}_{theme}.png')
    if i==1:
        for theme,color in [('light',(236,239,243)),('dark',(28,33,43))]:
            detail=Image.new('RGBA',(800,340),color+(255,))
            for k,pos in [(3,(24,40)),(15,(580,40))]:detail.alpha_composite(Image.open(ROOT/m['items'][k-1]['file']).convert('RGBA'),pos)
            detail.convert('RGB').save(ROOT/f'changed_items_{theme}.png')
checks=[]
for r in m['items']:
    p=ROOT/r['file'];im=Image.open(p);arr=np.array(im);b=im.getbbox();w,h=b[2]-b[0],b[3]-b[1]
    assert im.mode=='RGBA' and (w,h)==(r['bbox_width'],r['bbox_height']) and w%4==h%4==0
    assert math.ceil(w/256)*math.ceil(h/256)==r['total_cells']<=10
    assert np.all(arr[arr[:,:,3]==0,:3]==0) and np.any((arr[:,:,3]>0)&(arr[:,:,3]<255))
    assert min(b[0],b[1],im.width-b[2],im.height-b[3])>=20
    if r['id'] not in changed:assert p.read_bytes()==(BASE/r['file']).read_bytes()
    placed=np.array(atlases[r['atlas']-1].crop((r['sheet_x'],r['sheet_y'],r['sheet_right'],r['sheet_bottom'])))
    assert np.array_equal(placed,arr[b[1]:b[3],b[0]:b[2]])
    checks.append(dict(id=r['id'],bbox=[w,h],cells=r['total_cells']))
assert np.array_equal(before[0][~allowed],np.array(atlases[0])[~allowed])
assert (ROOT/'atlas_2_3840x2160.png').read_bytes()==(BASE/'atlas_2_3840x2160.png').read_bytes()
m.update(baseline=str(BASE),changed_ids=changed,unchanged_ids=[k for k in range(1,93) if k not in changed],new_source_pixels={str(ROOT/'source.png'):[3840,2160]})
(ROOT/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
with (ROOT/'coordinates.csv').open('w',encoding='utf-8-sig',newline='') as f:
    wr=csv.DictWriter(f,fieldnames=list(dict.fromkeys(k for r in m['items'] for k in r)));wr.writeheader();wr.writerows(m['items'])
v=dict(result='PASS',actual_source_pixels=[3840,2160],changed_ids=changed,unchanged_individual_png_byte_identical_count=90,atlas1_outside_patch_pixels_identical=True,atlas2_png_byte_identical=True,actual_alpha_bbox_divisible_by4=True,grid_allocation_preserved=True,fractional_alpha_retained=True,transparent_rgb_zero=True,items=checks)
(ROOT/'validation.json').write_text(json.dumps(v,ensure_ascii=False,indent=2),encoding='utf-8')
idx=json.loads((BASE/'catalog_92_delivery_index.json').read_text(encoding='utf-8'));idx['current_baseline']=str(ROOT)
for e,r in zip(idx['items'],m['items']):
    e.update(file=str(ROOT/r['file']),atlas=str(ROOT/r['atlas_file']),bbox_width=r['bbox_width'],bbox_height=r['bbox_height'],sheet_x=r['sheet_x'],sheet_y=r['sheet_y'],operation=r['operation'])
(ROOT/'catalog_92_delivery_index.json').write_text(json.dumps(idx,ensure_ascii=False,indent=2),encoding='utf-8')
with (ROOT/'catalog_92_delivery_index.csv').open('w',encoding='utf-8-sig',newline='') as f:
    wr=csv.DictWriter(f,fieldnames=list(idx['items'][0]));wr.writeheader();wr.writerows(idx['items'])
(ROOT/'README.md').write_text('''# C96与普通手雷局部重绘

基准：../batch09_visibility_tiles/。仅修改03毛瑟C96及15普通手雷，其余90张独立PNG字节一致；第一张合集两处替换区域以外像素一致，第二张合集PNG字节一致。两件仍分别占2格、1格，保留显示上限与自身长宽比。

模型gpt-image-2.5，quality auto；请求4K，接口实际3840×2160。对两件进行独立高分辨率重绘后，本地透明去底、清边、预乘Alpha Lanczos采样与无损替换，无JPEG中间格式。最终PNG保存后重新核验实际Alpha>0包围框宽高均为4的倍数，半透明边缘保留、透明RGB为0、四周至少24px留白。

C96修正为短固定弹仓、扫帚柄木握把、连续机匣与长枪管、明确扳机及护圈，统一宽大切面的光影；普通手雷修正顶部拉环和贴身保险杆连接，保持完整蛋形轮廓和少量大块切面。木柄手雷未修改。

atlas_1/2_3840x2160.png为两张透明合集，individual/为92张PNG，changed_items_*为两件原尺寸深浅背景预览，preview_*为完整预览，grid_*为网格检查；prompt.txt为完整提示词；source.png为接口4K源图；manifest.json、coordinates.csv、validation.json记录坐标及一致性验证。其他物品与历史材质待办保持基准状态。
''',encoding='utf-8')
paths=[ROOT/r['file'] for r in m['items']]+[ROOT/f'atlas_{i}_3840x2160.png' for i in (1,2)]
(ROOT/'SHA256SUMS.txt').write_text('\n'.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.relative_to(ROOT).as_posix() for p in paths)+'\n',encoding='utf-8')
archive=ROOT.parent/'batch10_c96_grenade_fixed.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in sorted(ROOT.rglob('*')):
        if p.is_file():z.write(p,p.relative_to(ROOT))
with zipfile.ZipFile(archive) as z:assert z.testzip() is None
print(json.dumps(dict(result='PASS',archive=str(archive),changes=[{k:r[k] for k in ['id','bbox_width','bbox_height','total_cells']} for r in m['items'] if r['id'] in changed]),ensure_ascii=False))
