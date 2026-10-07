"""Detailed 32px companions. Small menu-bar sprites remain in mascot.py.

Parts move independently on an eight-frame clock; the grounded body never bobs.
These are original pixel drawings inspired by the supplied character references.
"""
from math import sin, pi

SIZE = 32
FIGURES = ('robot', 'rooster', 'rabbit', 'snowman', 'palm', 'orb', 'antenna')

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
        # Plush oval face, restrained muzzle, and one soft folding ear.
        fold=(0,0,1,2,3,2,1,0)[f]
        c.ellipse(7,1,13,16,'#');c.ellipse(8,2,12,15,'f');c.ellipse(9,4,11,12,'p')
        c.poly([(20,2+fold),(24,1+fold),(27,5+fold),(24,16),(19,15)],'#')
        c.poly([(21,3+fold),(24,3+fold),(25,6+fold),(23,15),(20,14)],'f')
        c.line(23,5+fold,21,12,'p')
        c.ellipse(10,23,23,31,'#');c.ellipse(11,24,22,30,'f');c.ellipse(13,25,20,29,'b')
        c.ellipse(6,28,13,31,'#');c.ellipse(7,29,12,30,'f')
        c.ellipse(20,28,27,31,'#');c.ellipse(21,29,26,30,'f')
        c.ellipse(4,10,28,26,'#');c.ellipse(5,11,27,25,'s');c.ellipse(5,11,26,24,'f')
        c.ellipse(9,18,23,24,'b')
        c.eye(10,14,eyes);c.eye(20,14,eyes)
        c.rect(7,19,9,20,'p');c.rect(24,19,25,20,'p')
        c.rect(15,19,17,19,'p');c.put(16,20,'p')
        c.put(16,21,'#');c.put(15,22,'#');c.put(17,22,'#')
        c.line(8,12,11,12,'w')
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
        nod=(0,0,0,1,1,0,0,0)[f];wing=(0,0,0,1,1,0,0,0)[f]
        # Slim neck, compact head, and long legs with alternating toe lifts.
        c.poly([(21,19),(24,8),(27,7),(27,22)],'#')
        c.poly([(24,21),(29,11),(30,12),(28,24)],'#')
        c.poly([(23,18),(25,10),(26,10),(25,21)],'b')
        c.line(27,17,29,13,'f')
        c.ellipse(9,16,28,25,'#');c.ellipse(10,17,27,24,'s');c.ellipse(11,17,26,23,'f')
        c.ellipse(14,18+wing,24,23,'s');c.ellipse(14,18+wing,22,22,'b')
        c.line(16,20+wing,20,20+wing,'f')
        c.rect(10,12,16,20,'#');c.rect(11,13,15,19,'f');c.rect(12,14,14,18,'b')
        c.ellipse(6+nod,5+nod,17+nod,15+nod,'#');c.ellipse(7+nod,6+nod,16+nod,14+nod,'f')
        c.ellipse(8+nod,6+nod,14+nod,12+nod,'b')
        for x,y in [(7,2),(10,1),(13,3)]:
            c.ellipse(x+nod,y+nod,x+2+nod,6+nod,'r')
        c.put(8+nod,3+nod,'p');c.put(11+nod,2+nod,'p')
        c.ellipse(6+nod,12+nod,8+nod,16+nod,'r')
        c.poly([(6+nod,9+nod),(2+nod,11+nod),(6+nod,12+nod)],'#')
        c.line(3+nod,11+nod,6+nod,11+nod,'a')
        c.eye(9+nod,7+nod,eyes)
        left=f in (2,3);right=f in (6,7)
        for x,lift,dx in [(13,left,1),(22,right,-1)]:
            end=30 if lift else 31;toe=x+dx if lift else x
            c.line(x,25,x,28,'a');c.line(x,28,toe,end,'a')
            c.line(toe-2,end,toe+2,end,'a')
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
    elif figure=='orb':
        # Limbless pearl sphere: a rolling highlight, diagonal oval eyes.
        roll=(0,0,1,2,2,1,0,-1)[f]
        c.ellipse(2,3,29,31,'#');c.ellipse(3,4,28,30,'s')
        c.ellipse(3,4,27,28,'f');c.ellipse(4,5,25,24,'b')
        c.ellipse(6+roll,6,16+roll,12,'w')
        for x,y in [(10,14),(21,11)]:
            if eyes=='shut': c.line(x,y+3,x+3,y+3,'#')
            else:
                c.ellipse(x-1,y,x+2,y+4,'#');c.ellipse(x,y+2,x+3,y+6,'#')
                if eyes!='wide': c.put(x+(1 if eyes=='glance' else 0),y,'w')
    elif figure=='antenna':
        bend=(0,0,1,2,1,0,-1,0)[f];wave=(0,0,-1,-2,-2,-1,0,0)[f]
        c.line(10,8,7+bend,3,'#');c.line(7+bend,3,4+bend,2,'r')
        c.line(21,8,25-bend,3,'#');c.line(25-bend,3,28-bend,2,'r')
        c.rect(10,25,14,30,'#');c.rect(20,25,24,30,'#')
        c.rect(11,26,13,30,'f');c.rect(21,26,23,30,'f')
        c.rect(10,31,14,31,'s');c.rect(20,31,24,31,'s')
        c.ellipse(4,6,28,27,'#');c.ellipse(5,7,27,26,'s')
        c.ellipse(5,7,26,24,'f');c.ellipse(7,7,23,15,'r')
        c.ellipse(8,8,14,10,'p')
        c.ellipse(1,14,7,21,'#');c.ellipse(1,14,6,20,'f')
        c.ellipse(25,14+wave,31,21+wave,'#');c.ellipse(26,14+wave,30,20+wave,'f')
        for x in (10,20):
            c.ellipse(x-1,12,x+4,18,'h')
            if eyes=='shut': c.line(x,15,x+2,15,'l')
            else:
                c.ellipse(x,13,x+2,15,'l')
                if eyes!='wide': c.put(x+(1 if eyes=='glance' else 0),13,'w')
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
            if figure == 'antenna': palettes[f'{figure}/{name}'].update(r='#fb5966', l='#45d8d1')
            if figure == 'rooster': palettes[f'{figure}/{name}']['r'] = '#b9719c'
    return {'width':SIZE,'height':SIZE,
            'sprites':{f'{fig}/{eye}/{f}':sprite(fig,eye,f) for fig in FIGURES for eye in eyes for f in range(frames)},
            'palettes':palettes}
