from pathlib import Path
from collections import deque
import ast,copy,json,csv,math,zipfile,sys
import numpy as np
from PIL import Image,ImageDraw,ImageFilter
ROOT=Path(__file__).resolve().parent
count=int(sys.argv[1]) if len(sys.argv)>1 else 1
files=[f'source_{i}.png' for i in range(1,count+1)]
sources=[Image.open(ROOT/f) for f in files]
assert all(im.size==(3840,2160) and im.format=='PNG' for im in sources)
groups=json.loads((ROOT/'roster.json').read_text(encoding='utf-8'))
prev=(ROOT.parent/'characters01_re_trio/process.py').read_text(encoding='utf-8');exec(prev[prev.index('tree=ast.parse'):prev.index('info=[')])
def components(mask,n):
    # Label connected foreground by scanline runs; x extents may overlap.
    runs=[];parent=[];last=[]
    def root(i):
        while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
        return i
    for y,row in enumerate(mask):
        edges=np.flatnonzero(np.diff(np.r_[False,row,False]));cur=[];q=0
        for a,b in zip(edges[::2],edges[1::2]):
            j=len(runs);runs.append((y,int(a),int(b)));parent.append(j);cur.append((a,b,j))
            while q<len(last) and last[q][1]<a:q+=1
            for c,d,i in last[q:]:
                if c>b:break
                parent[root(j)]=root(i)
        last=cur
    grouped={}
    for i,r in enumerate(runs):grouped.setdefault(root(i),[]).append(r)
    large=sorted(grouped.values(),key=lambda g:sum(b-a for y,a,b in g),reverse=True)[:n]
    assert len(large)==n and min(sum(b-a for y,a,b in c) for c in large)>50000,'characters touching or missing'
    return sorted(large,key=lambda c:sum((b-a)*(b+a) for y,a,b in c)/sum(b-a for y,a,b in c))
records=[];(ROOT/'individual').mkdir(exist_ok=True)
for g,(src,roster) in enumerate(zip(sources,groups),1):
    a=np.array(src.convert('RGBA'));natives=[]
    for comp in components(a[:,:,:3].min(2)<240,len(roster)):
        l=min(x for y,x,r in comp);r=max(r for y,x,r in comp);t=comp[0][0];b=comp[-1][0]+1
        assert min(l,t,3840-r,2160-b)>4,('clipped',g,l,t,r,b)
        crop=(l-4,t-4,r+4,b+4);p=a[t-4:b+4,l-4:r+4].copy();m=np.zeros(p.shape[:2],np.uint8)
        for y,x,z in comp:m[y-t+4,x-l+4:z-l+4]=255
        support=np.array(Image.fromarray(m).filter(ImageFilter.MaxFilter(7)))>0
        p[~support]=255
        im=clean_asset(Image.fromarray(p),full=True)
        # Preserve bright opaque hair/eyes while retaining open silhouette gaps.
        ar=np.array(im);solid=np.array(Image.fromarray(m).filter(ImageFilter.MinFilter(3)))>0
        solid[round((b-t)*.17):]=False;ar[solid]=p[solid]
        im=Image.fromarray(ar);im,removed=remove_specks(im.crop(im.getbbox()));natives.append((im,crop,removed))
    factor=min(1184/max(im.height for im,_,_ in natives),508/max(im.width for im,_,_ in natives),1)
    sheet=Image.new('RGBA',(3840,2160))
    for j,((slug,name,_),(im,crop,removed)) in enumerate(zip(roster,natives)):
        im,delta=resize_actual(im,[im.width*factor,im.height*factor]);w,h=im.size;cells=math.ceil(w/256)*math.ceil(h/256)
        assert w%4==h%4==0 and cells<=10
        x=((15-2*len(roster))//2+2*j)*256+(512-w)//2;y=1792-h
        sheet.paste(im,(x,y));path=f'individual/{len(records)+1:02d}_{slug}.png';p=Image.new('RGBA',(w+48,h+48));p.paste(im,(24,24));p.save(ROOT/path)
        ck=Image.open(ROOT/path);z=np.array(ck);assert ck.getbbox()==(24,24,w+24,h+24) and np.all(z[z[:,:,3]==0,:3]==0) and np.any((z[:,:,3]>0)&(z[:,:,3]<255))
        records.append(dict(id=len(records)+1,name=name,file=path,sheet=g,x=x,y=y,width=w,height=h,cells=cells,source_crop=crop,source=files[g-1],rounding_delta=delta))
    sheet.save(ROOT/f'characters_{g}_3840x2160.png')
    for theme,c in [('dark','#1c212b'),('light','#eceff3')]:
        bg=Image.new('RGBA',sheet.size,c);bg.alpha_composite(sheet);bg.convert('RGB').save(ROOT/f'preview_{g}_{theme}.png')
        if theme=='dark':
            l,t,r,b=sheet.getbbox();p=bg.crop((l-24,t-24,r+24,b+24)).convert('RGB');p.thumbnail((1536,720));p.save(ROOT/f'preview_{g}_compact.png')
        d=ImageDraw.Draw(bg)
        for x in range(0,3840,256):d.line((x,0,x,2048),fill='#9ca5ab')
        for y in range(0,2049,256):d.line((0,y,3840,y),fill='#9ca5ab')
        bg.convert('RGB').save(ROOT/f'grid_{g}_{theme}.png')
assert len(records)==sum(len(g) for g in groups[:count])
(ROOT/'manifest.json').write_text(json.dumps(dict(result='PASS',model='gpt-image-2.5',quality='auto',source_size=[3840,2160],source_files=files,grid_px=256,padding=24,relative_heights='preserved within each source sheet',items=records),ensure_ascii=False,indent=2),encoding='utf-8')
with (ROOT/'coordinates.csv').open('w',encoding='utf-8-sig',newline='') as f:
    wr=csv.DictWriter(f,fieldnames=list(records[0]));wr.writeheader();wr.writerows(records)
archive=ROOT.parent/(ROOT.name+('' if count==1 else f'_groups_1_to_{count}')+'.zip')
rows=[]
for g in range(1,count+1):
    sheet=Image.open(ROOT/f'characters_{g}_3840x2160.png');b=sheet.getbbox()
    crop=sheet.crop((b[0]-24,b[1]-24,b[2]+24,b[3]+24));crop.thumbnail((1440,550),Image.Resampling.LANCZOS);rows.append(crop)
for theme,color in [('dark','#1c212b'),('light','#eceff3')]:
    overview=Image.new('RGBA',(1488,sum(i.height+20 for i in rows)+20),color);y=20
    for row in rows:overview.alpha_composite(row,((1488-row.width)//2,y));y+=row.height+20
    overview.convert('RGB').save(ROOT/f'overview_{theme}.png')
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,6) as z:
    for p in ROOT.rglob('*'):
        if p.is_file() and (not p.name.startswith('source_') or p.name in files) and not p.name.startswith('review_'):z.write(p,p.relative_to(ROOT))
with zipfile.ZipFile(archive) as z:assert z.testzip() is None
print(f'PASS: {len(records)} distinct characters, {count} transparent 4K atlases')

