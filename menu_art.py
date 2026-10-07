"""Purpose-drawn 22px menu icons: large faces, distinct silhouettes, no status glyph.

These are independent from the 32px desktop drawings. Wity keeps its original art.
"""
SIZE = 22
FIGURES = ('crab', 'robot', 'rooster', 'rabbit', 'snowman', 'palm', 'orb', 'antenna')
class Canvas:
    def __init__(self): self.p = [['.']*SIZE for _ in range(SIZE)]
    def put(self,x,y,c):
        if 0<=x<SIZE and 0<=y<SIZE: self.p[y][x]=c
    def rect(self,x0,y0,x1,y1,c):
        for y in range(y0,y1+1):
            for x in range(x0,x1+1): self.put(x,y,c)
    def oval(self,x0,y0,x1,y1,c):
        rx=(x1-x0+1)/2;ry=(y1-y0+1)/2;cx=(x0+x1)/2;cy=(y0+y1)/2
        for y in range(y0,y1+1):
            for x in range(x0,x1+1):
                if ((x-cx)/rx)**2+((y-cy)/ry)**2<=1:self.put(x,y,c)
    def line(self,x0,y0,x1,y1,c):
        n=max(abs(x1-x0),abs(y1-y0),1)
        for i in range(n+1): self.put(round(x0+(x1-x0)*i/n),round(y0+(y1-y0)*i/n),c)
    def outline(self):
        edges=[(x,y) for y in range(SIZE) for x in range(SIZE) if self.p[y][x]=='.' and any(0<=x+dx<SIZE and 0<=y+dy<SIZE and self.p[y+dy][x+dx]!='.' for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)))]
        for x,y in edges:self.put(x,y,'#')
    def eye(self,x,y,eyes,ink='#',width=3):
        if eyes=='shut': self.line(x,y+2,x+width-1,y+2,ink)
        elif eyes=='squint': self.rect(x,y+1,x+width-1,y+2,ink)
        else:
            self.rect(x,y,x+width-1,y+3,ink)
            if eyes!='wide':self.put(x+(1 if eyes=='glance' else 0),y,'w')
    def rows(self):return [''.join(r) for r in self.p]

def sprite(figure,eyes,frame):
    c=Canvas(); blink=eyes;f=frame%8
    if figure=='robot':
        c.rect(4,4,17,16,'f');c.rect(3,6,18,14,'f')
        c.rect(1,8,2,12,'s');c.rect(19,8,20,12,'s')
        c.rect(9,2,11,3,'s');c.put(10,1,'e' if f<4 else 'w')
        c.rect(6,17,15,19,'s');c.rect(6,20,8,20,'f');c.rect(13,20,15,20,'f')
        c.outline();c.rect(5,7,16,13,'v');c.eye(6,8,blink,'e');c.eye(13,8,blink,'e')
        c.rect(9,15,12,15,'b');c.rect(6,4,13,4,'w')
    elif figure=='rooster':
        c.oval(6,12,18,17,'f');c.oval(16,8,19,15,'s')
        c.rect(8,9,11,14,'f');c.oval(4,4,13,11,'f')
        c.rect(5,1,6,4,'p');c.rect(8,0,9,4,'p');c.rect(11,2,12,4,'p')
        c.outline();c.eye(6,6,blink,width=2)
        c.line(2,9,4,9,'o');c.put(5,11,'p');c.oval(10,13,15,15,'b')
        for x,lift in [(9,f in (2,3)),(15,f in (6,7))]:
            y=19 if lift else 20;c.line(x,18,x,y,'o');c.line(x-1,y,x+1,y,'o')
        c.put(10,5,'w')
    elif figure=='rabbit':
        c.rect(5,2,8,10,'f');c.rect(14,2,17,10,'f')
        c.oval(3,8,19,20,'f');c.rect(5,20,8,20,'s');c.rect(14,20,17,20,'s');c.outline()
        c.rect(6,3,7,8,'p');c.rect(15,3,16,8,'p')
        if f in (4,5):c.put(6,3,'f');c.put(7,3,'f')
        c.oval(7,15,15,19,'b');c.eye(6,11,blink);c.eye(14,11,blink)
        c.put(4,15,'p');c.put(18,15,'p');c.rect(10,15,11,15,'p')
        c.put(10,17,'#');c.put(11,17,'#');c.put(9,16,'#');c.put(12,16,'#')
    elif figure=='snowman':
        c.oval(4,12,18,20,'f');c.oval(5,5,17,14,'f')
        c.rect(7,1,15,4,'v');c.rect(4,5,18,5,'v')
        c.line(2,12,4,15,'s');c.line(18,15,20,12,'s');c.outline()
        c.rect(7,3,15,3,'p');c.put(8+(f//2),2,'w')
        c.eye(7,8,blink,width=2);c.eye(13,8,blink,width=2)
        c.rect(10,11,13,11,'o');c.put(11,12,'o')
        c.rect(5,14,17,14,'p');c.rect(6,15,7,17,'p');c.put(12,17,'#');c.put(12,19,'#')
    elif figure=='palm':
        c.rect(9,8,12,19,'s');c.rect(7,20,15,20,'b')
        for tip in [(2,3),(4,1),(10,1),(17,1),(20,4),(19,8),(2,8)]:
            c.line(11,6,*tip,'f');c.line(10,7,tip[0],min(9,tip[1]+1),'f')
        c.oval(5,7,16,13,'b');c.outline()
        c.eye(6,8,blink,width=2);c.eye(13,8,blink,width=2);c.rect(10,12,11,12,'#')
        c.put(6,12,'p');c.put(15,12,'p');c.put(10,17,'b')
        if f in (2,3):c.put(19,7,'w')
    elif figure=='orb':
        c.oval(2,2,20,20,'f');c.outline()
        c.oval(4,4,17,17,'b');c.line(7,19,15,19,'s');c.put(17,17,'s');c.put(18,15,'s')
        c.rect(6+f//3,5,8+f//3,5,'w');c.put(5,6,'w')
        if blink in ('shut','squint'):
            c.line(6,11,9,12,'#');c.line(13,9,16,10,'#')
            if blink=='squint':c.line(6,10,9,11,'#');c.line(13,8,16,9,'#')
        else:
            c.line(6,8,9,12,'#');c.line(7,8,10,12,'#');c.line(13,7,16,11,'#');c.line(14,7,17,11,'#')
            if blink=='glance':c.put(7,9,'w');c.put(14,8,'w')
            if blink=='wide':c.put(5,9,'#');c.put(12,8,'#')
    elif figure=='antenna':
        c.oval(4,5,18,18,'f');c.oval(1,10,5,13,'s');c.oval(18,10,20,13,'s')
        c.rect(7,18,9,20,'f');c.rect(14,18,16,20,'f')
        c.line(6,5,4+(1 if f in (2,3) else 0),2,'f');c.line(16,5,18-(1 if f in (6,7) else 0),2,'f');c.outline()
        c.eye(7,8,blink,'v');c.eye(13,8,blink,'v')
        if blink not in ('shut','squint'):
            c.put(8,9,'e');c.put(14,9,'e')
        c.rect(9,14,12,14,'v');c.put(6,13,'p');c.put(17,13,'p');c.put(8,6,'w')
    elif figure=='crab':
        c.oval(4,7,17,19,'f');c.rect(3,19,6,20,'s');c.rect(15,19,18,20,'s')
        c.line(3,14,1,11,'f');c.line(18,14,20,11,'f');c.oval(1,4,4,10,'f');c.oval(17,4,20,10,'f');c.outline()
        c.put(2,5,'b');c.put(19,5,'b');c.eye(6,9,blink);c.eye(13,9,blink)
        c.rect(9,15,12,15,'#');c.put(5,14,'p');c.put(16,14,'p')
        if f in (4,5):c.put(2,8,'w')
    else:raise ValueError(figure)
    return c.rows()

def export(skins,frames):
    sprites={f'{fig}/{eyes}/{f}':sprite(fig,eyes,f) for fig in FIGURES for eyes in ('open','shut','wide','squint','glance') for f in range(frames)}
    palettes={}
    for fig in FIGURES:
        for skin,p in skins.items():
            palettes[f'{fig}/{skin}']={'#':p['outline'],'f':p['fur'],'s':p['fur_dark'],'b':p['pale'],'w':p['shine'],'p':p['blush'],'v':'#203047','e':'#83e2df','o':'#cd8a48'}
    return {'width':SIZE,'height':SIZE,'sprites':sprites,'palettes':palettes}
