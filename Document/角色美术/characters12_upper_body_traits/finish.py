from pathlib import Path
from collections import deque
from PIL import Image,ImageDraw,ImageFilter,ImageFont
import numpy as np
import ast,copy,json,math,shutil,hashlib,csv,zipfile
ROOT=Path(__file__).resolve().parent;BASE=ROOT.parent/'characters07_weathered_survivors'
src=Image.open(ROOT/'edited_source.png');assert src.size==(3840,2160) and src.format=='PNG';src=src.convert('RGBA')
prev=(ROOT.parent/'characters01_re_trio/process.py').read_text(encoding='utf-8');exec(prev[prev.index('tree=ast.parse'):prev.index('info=[')])
meta=json.loads((BASE/'manifest.json').read_text(encoding='utf-8'));regions=json.loads((ROOT/'regions.json').read_text(encoding='utf-8'));updates={}
def center_head(im):
    a=np.array(im.getchannel('A'));y,x=np.nonzero(a[:int(im.height*.135)]>150);return float(np.median(x))
for j,r in enumerate(regions):
    old=Image.open(BASE/r['file']);old=old.crop(old.getbbox());w,h=old.size;i=r['id']
    new=clean_asset(src.crop((j*960,0,(j+1)*960,2160)));new,_=remove_specks(new)
    s=h/new.height;nw=round(new.width*s);nw=min(nw,504 if i==15 else 512)
    new=resize_premult(new,(nw,h));x=round(center_head(old)-center_head(new));pad=64
    a=Image.new('RGBA',(w+2*pad,h));a.paste(old,(pad,0));b=Image.new('RGBA',a.size);b.paste(new,(pad+x,0));
    a0=np.array(a);b0=np.array(b)
    if i==13:
        # Match the two trouser legs where the repaired knee joins the original boot-side fabric.
        mid=pad+w//2;target=int(h*.804);end=int(h*.84);start=int(h*.67)
        for l,r in [(0,mid),(mid,a.width)]:
            def bounds(ar):
                ix=np.flatnonzero(ar[target,l:r,3]>128);return (ix[0]+l,ix[-1]+l) if len(ix) else None
            old_bounds,new_bounds=bounds(a0),bounds(b0)
            if old_bounds is None or new_bounds is None:continue
            o1,o2=old_bounds;n1,n2=new_bounds
            for y in range(start,end):
                weight=min(1,(y-start)/max(1,target-start));xs=np.arange(l,r)
                mapping=n1+(xs-o1)*(n2-n1)/max(1,o2-o1);q=xs+(mapping-xs)*weight
                ix=np.floor(q).astype(int);v=(q-ix)[:,None];ix=np.clip(ix,l,r-2)
                row=b0[y].copy();u=row[ix].astype(float);wrow=row[ix+1].astype(float)
                al=u[:,3:4]*(1-v)+wrow[:,3:4]*v
                rgb=(u[:,:3]*u[:,3:4]*(1-v)+wrow[:,:3]*wrow[:,3:4]*v)/np.maximum(al,1e-8)
                b0[y,l:r]=np.rint(np.concatenate((rgb,al),axis=1)).clip(0,255).astype(np.uint8)
    # Keep the exact prior head and lower silhouette. Match the replacement
    # to the existing pose using the head center and native standing height.
    yy,xx=np.ogrid[:h,:a.width];cx=pad+center_head(old)
    lo,hi={6:(.17,.435),8:(.16,.315),13:(.146,.82),15:(.175,.641)}[i]
    f=np.clip(np.minimum(yy-h*lo,h*hi-yy)/12,0,1);f=np.broadcast_to(f,(h,a.width)).copy()
    if i==13:
        # Include raised axe beside the head, keeping the face itself untouched.
        f=np.maximum(f,np.clip(np.minimum(yy-h*.045,h*.20-yy)/10,0,1)*np.clip((cx-68-xx)/12,0,1))
    if i in (6,8):
        half=round(w*(.26 if i==6 else .30));f*=np.clip((half-abs(xx-cx))/12,0,1)
        f*=a0[:,:,3]>0
    # Blend straight-alpha layers through premultiplied channels only at seams.
    aa=a0[:,:,3]/255;bb=b0[:,:,3]/255;al=aa*(1-f)+bb*f
    rgb=(a0[:,:,:3]*aa[:,:,None]*(1-f[:,:,None])+b0[:,:,:3]*bb[:,:,None]*f[:,:,None])/np.maximum(al[:,:,None],1e-8)
    out=np.dstack((np.rint(rgb).clip(0,255).astype(np.uint8),np.rint(al*255).astype(np.uint8)));out[f==0]=a0[f==0];out[out[:,:,3]==0,:3]=0
    assert np.array_equal(out[f==0],a0[f==0]);im=Image.fromarray(out);l,t,rr,d=im.getbbox()
    # 1–3px outward rounding only via shifting a boundary-edge pixel to its
    # neighboring transparent pixel, preserving all unedited body pixels.
    if (rr-l)%4 or (d-t)%4:
        # Trim negligible new edge pixels only in the editable region.
        for _ in range((rr-l)%4):
            if not np.any(a0[:,rr-1,3]):out[:,rr-1]=0;rr-=1
            elif not np.any(a0[:,l,3]):out[:,l]=0;l+=1
            else:raise ValueError((i,'protected width'))
        im=Image.fromarray(out);l,t,rr,d=im.getbbox()
    w2,h2=rr-l,d-t;assert w2%4==h2%4==0 and math.ceil(w2/256)*math.ceil(h2/256)<=10,(i,w2,h2)
    im=im.crop((l,t,rr,d));outpad=Image.new('RGBA',(w2+48,h2+48));outpad.paste(im,(24,24));updates[i]=(outpad,im,l-pad,t)
(ROOT/'individual').mkdir(exist_ok=True)
for g in range(1,4):
    path=f'characters_{g}_3840x2160.png';sheet=Image.open(BASE/path).convert('RGBA');draw=ImageDraw.Draw(sheet)
    for r in meta['items']:
        if r['sheet']!=g:continue
        p=ROOT/r['file'];i=r['id']
        if i not in updates:
            shutil.copy2(BASE/r['file'],p);assert p.read_bytes()==(BASE/r['file']).read_bytes();continue
        pad,im,dx,dy=updates[i];pad.save(p);x,y=r['x'],r['y'];draw.rectangle((x,y,x+r['width']-1,y+r['height']-1),fill=(0,0,0,0));sheet.paste(im,(x+dx,y+dy));r.update(x=x+dx,y=y+dy,width=im.width,height=im.height,cells=math.ceil(im.width/256)*math.ceil(im.height/256),source='edited_source.png',source_crop=None)
    sheet.save(ROOT/path)
    for theme,c in [('dark','#1c212b'),('light','#eceff3')]:
        bg=Image.new('RGBA',sheet.size,c);bg.alpha_composite(sheet);bg.convert('RGB').save(ROOT/f'preview_{g}_{theme}.png')
        d=ImageDraw.Draw(bg)
        for x in range(0,3840,256):d.line((x,0,x,2048),fill='#9ca5ab')
        for y in range(0,2049,256):d.line((0,y,3840,y),fill='#9ca5ab')
        bg.convert('RGB').save(ROOT/f'grid_{g}_{theme}.png')
meta.update(base=BASE.name,edited_ids=list(updates),unchanged_cutouts=13,actual_edit_source_px=[3840,2160],source_files=['edited_source.png'],protected_pixels_preserved=True)
(ROOT/'manifest.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
with (ROOT/'coordinates.csv').open('w',encoding='utf-8-sig',newline='') as f:
    wr=csv.DictWriter(f,fieldnames=list(meta['items'][0]));wr.writeheader();wr.writerows(meta['items'])
for theme,c in [('dark','#1c212b'),('light','#eceff3')]:
    board=Image.new('RGBA',(1320,870),c);d=ImageDraw.Draw(board);font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',25)
    for j,r in enumerate(regions):
        im=updates[r['id']][0].copy();im.thumbnail((306,805));board.alpha_composite(im,(330*j+(330-im.width)//2,48));d.text((330*j+165,24),meta['items'][r['id']-1]['name'],font=font,anchor='mm',fill='#e8e2d8' if theme=='dark' else '#30383c')
    board.convert('RGB').save(ROOT/f'changes_{theme}.png')
zpath=ROOT.parent/(ROOT.name+'.zip')
with zipfile.ZipFile(zpath,'w',zipfile.ZIP_DEFLATED,6) as z:
    for p in ROOT.rglob('*'):
        if p.is_file() and p.name not in ['audit.png','edit_review.png']:z.write(p,p.relative_to(ROOT))
with zipfile.ZipFile(zpath) as z:assert z.testzip() is None
print('PASS: four local edits, 13 original cutouts byte-identical')
