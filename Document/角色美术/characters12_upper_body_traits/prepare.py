from pathlib import Path
from PIL import Image,ImageDraw
import json
P=Path(__file__).resolve().parent;B=P.parent/'characters07_weathered_survivors'
data=json.loads((B/'manifest.json').read_text(encoding='utf-8'));im=Image.new('RGBA',(3840,2160),'white');m=Image.new('RGBA',im.size,(255,255,255,255));d=ImageDraw.Draw(m);records=[]
for j,(id,band) in enumerate([(6,(.16,.31)),(8,(.16,.28)),(13,(.14,.80)),(15,(.16,.63))]):
    rec=data['items'][id-1];a=Image.open(B/rec['file']);a=a.crop(a.getbbox());w,h=a.size;x=480+j*960-w//2;y=1720-h
    im.alpha_composite(a,(x,y));l,r=(x-12,x+w+12) if id in (6,8) else (x-100,x+w+100)
    box=(l,y+round(h*band[0]),r,y+round(h*band[1]));d.rectangle((box[0],box[1],box[2]-1,box[3]-1),fill=(255,255,255,0))
    records.append(dict(id=id,file=rec['file'],rect=list(box),xy=[x,y],size=[w,h]))
im.convert('RGB').save(P/'edit_input.png');m.save(P/'edit_mask.png');(P/'regions.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
