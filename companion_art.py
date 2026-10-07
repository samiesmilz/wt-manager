"""Detailed 32px companions. Small menu-bar sprites remain in mascot.py.

Parts move independently on an eight-frame clock; the grounded body never bobs.
These are original pixel drawings inspired by the supplied character references.
"""
from math import sin, pi

SIZE = 32
FIGURES = ('robot', 'rooster', 'rabbit', 'snowman', 'palm')

class Canvas:
    def __init__(self): self.p = [['.'] * SIZE for _ in range(SIZE)]
    def put(self, x, y, c):
        if 0 <= x < SIZE and 0 <= y < SIZE: self.p[y][x] = c
    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0,y1+1):
            for x in range(x0,x1+1): self.put(x,y,c)
    def ellipse(self, x0, y0, x1, y1, c):
        rx,ry=(x1-x0+1)/2,(y1-y0+1)/2;cx,cy=(x1+x0)/2,(y1+y0)/2
        for y in range(y0,y1+1):
            for x in range(x0,x1+1):
                if ((x-cx)/rx)**2+((y-cy)/ry)**2<=1: self.put(x,y,c)
    def line(self, x0,y0,x1,y1,c):
        n=max(abs(x1-x0),abs(y1-y0),1)
        for i in range(n+1): self.put(round(x0+(x1-x0)*i/n),round(y0+(y1-y0)*i/n),c)
    def poly(self, pts,c):
        for y in range(min(p[1] for p in pts),max(p[1] for p in pts)+1):
            xs=[]
            for (x0,y0),(x1,y1) in zip(pts,pts[1:]+pts[:1]):
                if min(y0,y1)<=y<max(y0,y1): xs.append(x0+(y-y0)*(x1-x0)/(y1-y0))
            xs.sort()
            for a,b in zip(xs[::2],xs[1::2]): self.rect(round(a),y,round(b),y,c)
        for a,b in zip(pts,pts[1:]+pts[:1]): self.line(*a,*b,c)
    def eye(self,x,y,eyes):
        if eyes=='shut': self.line(x,y+2,x+2,y+2,'#')
        elif eyes=='squint': self.rect(x,y+1,x+2,y+2,'#')
        else:
            self.rect(x,y,x+2,y+3,'#')
            if eyes!='wide': self.put(x+(1 if eyes=='glance' else 0),y,'w')
    def rows(self): return [''.join(r) for r in self.p]

def sprite(figure,eyes,frame):
    c=Canvas();f=frame%8
    if figure=='rabbit':
        # One ear folds at its tip. Body and paws remain planted.
        fold=(0,0,1,2,3,2,1,0)[f]
        c.poly([(6,3),(9,1),(12,4),(13,15),(7,15)],'#')
        c.poly([(7,4),(9,3),(11,5),(12,14),(8,14)],'f')
        c.poly([(8,5),(9,4),(10,6),(11,13),(9,13)],'p')
        c.poly([(20,3+fold),(23,1+fold),(26,4+fold),(24,16),(18,15)],'#')
        c.poly([(21,4+fold),(23,3+fold),(25,5+fold),(23,15),(20,14)],'f')
        c.line(23,5+fold,21,13,'p');c.line(24,6+fold,22,13,'p')
        c.ellipse(8,20,24,31,'#');c.ellipse(9,21,23,30,'s')
        c.ellipse(11,22,21,29,'f');c.ellipse(13,24,20,29,'b')
        c.ellipse(5,27,13,31,'#');c.ellipse(6,28,12,30,'f')
        c.ellipse(20,27,28,31,'#');c.ellipse(21,28,27,30,'f')
        c.ellipse(4,12,27,26,'#');c.ellipse(5,13,26,25,'s')
        c.ellipse(6,13,25,23,'f');c.ellipse(7,14,24,21,'f')
        c.ellipse(7,20,24,25,'b');c.ellipse(7,16,12,21,'b');c.ellipse(20,16,24,21,'b')
        c.eye(9,16,eyes);c.eye(21,16,eyes)
        c.rect(7,21,9,22,'p');c.rect(24,21,25,22,'p')
        c.rect(15,20,17,20,'p');c.put(16,21,'p');c.line(16,22,16,23,'#')
        c.line(13,23,15,24,'#');c.line(17,24,19,23,'#')
        c.line(6,24,8,24,'s');c.line(24,24,26,24,'s')
    elif figure=='snowman':
        wave=(0,0,-1,-2,-3,-2,-1,0)[f];flutter=(0,1,2,1,0,-1,-2,-1)[f]
        c.line(8,21,3,17+wave,'t');c.line(3,17+wave,1,14+wave,'t')
        c.line(3,17+wave,1,17+wave,'t');c.line(3,17+wave,4,13+wave,'t')
        c.line(24,21,28,16,'t');c.line(28,16,31,14,'t');c.line(28,16,28,12,'t')
        c.ellipse(6,19,25,31,'#');c.ellipse(7,20,24,30,'s');c.ellipse(8,20,23,28,'f')
        c.ellipse(9,21,18,25,'w');c.rect(15,23,16,24,'#');c.rect(15,28,16,29,'#')
        c.ellipse(8,8,23,21,'#');c.ellipse(9,9,22,20,'s');c.ellipse(9,9,21,18,'f')
        c.rect(9,18,22,20,'g');c.rect(10,18,20,18,'l')
        c.poly([(10,20),(13,20),(13+flutter,27),(10+flutter,27)],'g')
        c.line(11+flutter,24,12+flutter,24,'l')
        c.eye(11,11,eyes);c.eye(19,11,eyes)
        c.poly([(16,14),(22,15),(16,16)],'a');c.put(16,14,'q')
        c.put(12,16,'r');c.put(13,17,'r');c.put(14,18,'r');c.put(18,18,'r');c.put(19,17,'r')
        c.rect(8,2,22,8,'#');c.rect(10,3,21,7,'h');c.rect(10,3,12,5,'v')
        c.rect(8,7,22,8,'r');c.rect(6,9,25,10,'#');c.rect(7,9,23,9,'h')
        c.rect(9,6,11,7,'g');c.put(9,5,'l')
    elif figure=='rooster':
        peck=(0,0,1,3,1,0,2,0)[f];wing=(0,0,0,1,2,1,0,0)[f]
        # Fan tail, feather highlights, feet and a profile beak.
        for pts in [[(19,19),(22,6),(25,5),(25,21)],[(22,21),(27,7),(30,8),(29,23)],[(22,23),(30,13),(31,16),(28,25)]]:
            c.poly(pts,'#')
        c.poly([(21,18),(23,8),(24,8),(24,20)],'b');c.poly([(24,21),(28,10),(29,10),(27,23)],'f')
        c.line(26,20,29,15,'s')
        c.ellipse(8,15,28,29,'#');c.ellipse(9,16,27,28,'s');c.ellipse(10,16,26,26,'f')
        c.ellipse(12,17+wing,24,26,'s');c.ellipse(12,17+wing,22,24,'b')
        c.line(16,22+wing,21,22+wing,'f');c.line(17,24,21,24,'f')
        c.line(13,28,13,30,'a');c.line(20,28,20,30,'a');c.line(10,31,15,31,'a');c.line(18,31,23,31,'a')
        c.ellipse(6+peck,6+peck,17+peck,21+peck,'#');c.ellipse(7+peck,7+peck,16+peck,20+peck,'f')
        c.ellipse(8+peck,8+peck,14+peck,17+peck,'b')
        c.ellipse(6+peck,3+peck,9+peck,8+peck,'r');c.ellipse(9+peck,2+peck,12+peck,8+peck,'r');c.ellipse(12+peck,4+peck,15+peck,8+peck,'r')
        c.line(7+peck,4+peck,8+peck,4+peck,'p');c.put(10+peck,3+peck,'p')
        c.ellipse(6+peck,14+peck,9+peck,19+peck,'r')
        c.poly([(6+peck,11+peck),(2+peck,13+peck),(6+peck,15+peck)],'#')
        c.poly([(5+peck,12+peck),(3+peck,13+peck),(6+peck,14+peck)],'a')
        c.eye(9+peck,9+peck,eyes)
    elif figure=='palm':
        sway=(0,1,2,1,0,-1,-2,-1)[f]
        c.ellipse(6,28,28,31,'t');c.line(8,29,25,29,'b')
        c.poly([(18,11),(21,12),(24,29),(19,29),(18,21),(15,14)],'#')
        c.poly([(18,12),(20,13),(22,28),(20,28),(19,21),(16,14)],'t')
        for y in (16,19,22,25): c.line(18+(y-16)//4,y,20+(y-16)//4,y+1,'d')
        c.line(18,14,21,27,'q')
        # Each frond is a stepped pointed blade; tips flex more than roots.
        fronds=[[(17,11),(10,5),(4,5),(1,8+sway),(8,7),(15,13)],[(17,11),(12,3),(7,1),(5,2),(11,6),(15,13)],[(17,11),(18,3),(23,1),(26,2+sway),(21,5),(19,12)],[(18,12),(24,5),(30,6),(31,9+sway),(25,8),(20,14)],[(16,12),(7,10),(1,13+sway),(2,16+sway),(8,13),(16,15)],[(18,13),(26,12),(31,17+sway),(30,20+sway),(25,16),(18,15)],[(16,13),(11,16),(8,24+sway),(6,22+sway),(8,16),(14,12)]]
        for pts in fronds:
            c.poly(pts,'#'); cx=sum(x for x,y in pts)//len(pts);cy=sum(y for x,y in pts)//len(pts)
            c.poly([(round((x+cx)/2),round((y+cy)/2)) for x,y in pts],'g')
            c.line(17,12,pts[2][0],pts[2][1],'l')
        c.ellipse(12,11,16,16,'d');c.ellipse(19,12,23,17,'d')
        c.put(13,12,'q');c.put(20,13,'q')
        # A tiny face below the crown, never hidden by coconuts.
        c.eye(16,17,eyes);c.put(20,20,'#')
    elif figure=='robot':
        scan=(0,1,2,3,4,3,2,1)[f];antenna=(0,0,0,1,0,0,0,-1)[f]
        c.rect(11,23,14,29,'#');c.rect(19,23,22,29,'#');c.rect(11,24,13,28,'s');c.rect(19,24,21,28,'s')
        c.rect(8,29,14,31,'#');c.rect(18,29,24,31,'#');c.rect(9,29,13,30,'f');c.rect(19,29,23,30,'f')
        c.rect(9,18,23,25,'#');c.rect(10,19,22,24,'s');c.rect(11,19,21,23,'f')
        c.rect(13,20,19,22,'h');c.rect(14,20,18,20,'l');c.put(20,23,'w')
        c.rect(5,19,8,25,'#');c.rect(24,19,27,25,'#');c.rect(6,20,7,24,'s');c.rect(25,20,26,24,'s')
        c.line(16,3,16,6,'#');c.ellipse(14+antenna,1,18+antenna,4,'#');c.put(16+antenna,2,'l')
        c.rect(5,7,27,17,'#');c.rect(7,5,25,19,'#');c.rect(7,7,25,17,'s');c.rect(8,6,24,7,'f');c.rect(8,8,24,16,'f')
        c.rect(3,10,5,14,'#');c.rect(27,10,29,14,'#');c.rect(4,11,5,13,'v');c.rect(27,11,28,13,'v')
        c.rect(8,9,24,15,'h');c.rect(9,10,23,14,'v')
        c.eye(11,10,eyes);c.eye(20,10,eyes)
        c.rect(12,17,20,17,'h');c.put(12+scan*2,17,'l')
        c.line(8,6,12,6,'w');c.put(24,8,'w')
    else: raise ValueError(figure)
    return c.rows()

# Accessory colours are identity, never the live state. The framed badge is
# added by the native renderer and consumes the engine's mood and tint.
ACCESSORIES = {'h':'#202a3c','v':'#455d7e','r':'#bf4b58','g':'#277c60','l':'#83c58b',
               't':'#a87548','d':'#65422f','q':'#e7b879','a':'#edaa48'}

def export(skins, slots, eyes, frames):
    palettes={}
    for figure in FIGURES:
        for name,skin in skins.items():
            palettes[f'{figure}/{name}']={ch:skin[slot] for ch,slot in slots.items() if slot!='accent'} | ACCESSORIES
            if figure == 'rooster': palettes[f'{figure}/{name}']['r'] = '#b9719c'
    return {'width':SIZE,'height':SIZE,
            'sprites':{f'{fig}/{eye}/{f}':sprite(fig,eye,f) for fig in FIGURES for eye in eyes for f in range(frames)},
            'palettes':palettes}
