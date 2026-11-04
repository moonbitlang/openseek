"""Generate the public, synthetic PPTX fixture used by Office viewer tests."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED, ZipInfo
from struct import pack
import zlib
P='http://schemas.openxmlformats.org/presentationml/2006/main'
A='http://schemas.openxmlformats.org/drawingml/2006/main'
R='http://schemas.openxmlformats.org/officeDocument/2006/relationships'
Q='http://schemas.openxmlformats.org/package/2006/relationships'
C='http://schemas.openxmlformats.org/package/2006/content-types'
def shape(number,text,x,y,width,height,size,color='FFFFFF'):
    return f'<p:sp><p:nvSpPr><p:cNvPr id="{number}" name="Text {number}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="{x*12700}" y="{y*12700}"/><a:ext cx="{width*12700}" cy="{height*12700}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></p:spPr><p:txBody><a:bodyPr lIns="0" rIns="0" tIns="0" bIns="0"/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US" sz="{size*100}"><a:solidFill><a:srgbClr val="{color}"/></a:solidFill><a:latin typeface="Arial"/></a:rPr><a:t>{text}</a:t></a:r></a:p></p:txBody></p:sp>'
def picture(x,y,width,height):
    return f'<p:pic><p:nvPicPr><p:cNvPr id="5" name="Synthetic checkerboard"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed="image"/><a:srcRect l="10000" r="10000"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x="{x*12700}" y="{y*12700}"/><a:ext cx="{width*12700}" cy="{height*12700}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:ln w="19050"><a:solidFill><a:srgbClr val="55B6A4"/></a:solidFill></a:ln></p:spPr></p:pic>'
def slide(text,color):
    return f'<p:sld xmlns:p="{P}" xmlns:a="{A}" xmlns:r="{R}"><p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="{color}"/></a:solidFill></p:bgPr></p:bg><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>{text}</p:spTree></p:cSld></p:sld>'
parts={
 '[Content_Types].xml':f'<Types xmlns="{C}"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/><Override PartName="/ppt/slides/slide2.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/></Types>',
 '_rels/.rels':f'<Relationships xmlns="{Q}"><Relationship Id="main" Type="{R}/officeDocument" Target="ppt/presentation.xml"/></Relationships>',
 'ppt/presentation.xml':f'<p:presentation xmlns:p="{P}" xmlns:r="{R}"><p:sldIdLst><p:sldId id="256" r:id="first"/><p:sldId id="257" r:id="second"/></p:sldIdLst><p:sldSz cx="9144000" cy="5143500"/></p:presentation>',
 'ppt/_rels/presentation.xml.rels':f'<Relationships xmlns="{Q}"><Relationship Id="first" Type="{R}/slide" Target="slides/slide1.xml"/><Relationship Id="second" Type="{R}/slide" Target="slides/slide2.xml"/></Relationships>',
 'ppt/slides/slide1.xml':slide(shape(2,'PPTX preview',45,45,620,70,36)+shape(3,'Read-only slides. Selectable text.',45,135,610,60,20)+picture(45,225,270,95),'142F55'),
 'ppt/slides/slide2.xml':slide(shape(2,'Second slide',45,45,620,70,32,'142F55')+shape(3,'Search, zoom and page navigation',45,130,610,60,20,'142F55')+picture(365,225,300,110),'F1F5F9')}
for n in [1,2]:parts[f'ppt/slides/_rels/slide{n}.xml.rels']=f'<Relationships xmlns="{Q}"><Relationship Id="image" Type="{R}/image" Target="../media/checker.png"/></Relationships>'
def chunk(kind,data):return pack('>I',len(data))+kind+data+pack('>I',zlib.crc32(kind+data)&0xffffffff)
w,h=80,40
pixels=b''.join(b'\0'+b''.join(bytes((66,165,145) if (x//10+y//10)%2 else (248,205,85)) for x in range(w)) for y in range(h))
parts['ppt/media/checker.png']=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(pixels))+chunk(b'IEND',b'')
if __name__=='__main__':
 out=Path(__file__).with_name('static-slides.pptx')
 with ZipFile(out,'w',ZIP_DEFLATED) as z:
  for name,data in parts.items():
   info=ZipInfo(name,(2020,1,1,0,0,0));info.compress_type=ZIP_DEFLATED;z.writestr(info,data)
 print(out)
