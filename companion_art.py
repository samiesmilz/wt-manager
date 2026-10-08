"""Detailed 32px companions. Small menu-bar sprites remain in mascot.py.

Parts move independently on an eight-frame clock; the grounded body never bobs.
These are original pixel drawings inspired by the supplied character references.
"""
from math import sin, pi

WALK_FRAMES = 16

SIZE = 32
FIGURES = ('robot', 'rooster', 'rabbit', 'snowman', 'palm', 'orb', 'antenna')

class Canvas:
    def __init__(self, size=SIZE, height=None):
        self.width=size; self.height=height or size
        self.p = [['.'] * self.width for _ in range(self.height)]
    def put(self, x, y, c):
        if 0 <= x < self.width and 0 <= y < self.height: self.p[y][x] = c
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

WALKING_FIGURES = FIGURES + ('cat', 'crab')


# Eight planted poses followed by an airborne recovery. The swing overshoots
# the next contact slightly, visibly passing ahead of the weight-bearing foot.
STRIDE = (4,3,2,1,0,-1,-2,-3,-4,-3,-1,1,3,5,6,5)
LIFT = (0,0,0,0,0,0,0,0,1,2,3,4,4,3,2,1)

def foot_pose(hip, phase, floor=31):
    phase %= WALK_FRAMES
    return hip+STRIDE[phase], floor-LIFT[phase]

def _side_leg(c, hip, top, phase, fill='f', bird=False, floor=31, slim=False):
    toe,ground=foot_pose(hip,phase,floor)
    knee=hip+STRIDE[phase % WALK_FRAMES]//2
    knee_y=min(top+2,ground-1)
    if bird:
        c.line(hip,top,knee,knee_y,'a');c.line(knee,knee_y,toe,ground,'a')
        c.line(toe-1,ground,toe+1,ground,'a')
    else:
        for dx in ((0,) if slim else (-1,0,1)):
            c.line(hip+dx,top,knee+dx,knee_y,'#')
            c.line(knee+dx,knee_y,toe+dx,ground-1,'#')
        c.line(hip,top,knee,knee_y,fill);c.line(knee,knee_y,toe,ground-1,fill)
        c.rect(toe-1,ground-1,toe+1,ground,'#')
        c.put(toe,ground-1,fill)

def _original_profile(figure,eyes,phase):
    # The original characters keep their original 22x23 pixel grid. No size
    # or outline-weight jump when the front portrait becomes a profile.
    c=Canvas(22,23);g=phase%WALK_FRAMES
    if figure=='cat':
        _side_leg(c,7,18,g,'s',floor=22,slim=True)
        _side_leg(c,13,18,(g+8)%16,'s',floor=22,slim=True)
        c.poly([(7,19),(2,16),(0,9),(1,3),(4,0),(6,2),(5,7),(3,10),(4,14),(8,17)],'#')
        c.poly([(6,17),(3,14),(2,8),(3,3),(4,2),(4,6),(2,10),(4,15)],'s')
        c.line(2,5,2,8,'w')
        c.ellipse(5,13,17,20,'#');c.ellipse(6,14,16,19,'f')
        c.ellipse(8,15,15,19,'b')
        c.poly([(8,10),(7,4),(11,5),(13,10)],'#')
        c.poly([(9,8),(9,6),(11,7)],'s')
        c.ellipse(7,6,19,17,'#');c.ellipse(8,7,18,16,'f')
        c.poly([(14,8),(15,3),(19,5),(20,10)],'#')
        c.poly([(16,7),(16,5),(18,6)],'p')
        c.ellipse(16,12,21,16,'#');c.ellipse(17,13,20,15,'b');c.put(21,13,'p')
        c.eye(16,9,eyes);c.put(18,16,'#')
        _side_leg(c,8,18,(g+8)%16,floor=22,slim=True)
        _side_leg(c,14,18,g,floor=22,slim=True)
    else:
        for i,hip in enumerate((7,11,15)):
            _side_leg(c,hip,18,(g+8+i*4)%16,'s',floor=22,slim=True)
        c.line(7,15,4,11,'#');c.ellipse(0,7,6,13,'#');c.ellipse(1,8,5,12,'s')
        c.poly([(0,8),(3,10),(0,11)],'.')
        c.ellipse(4,13,17,19,'#');c.ellipse(5,14,16,18,'f');c.line(7,15,13,15,'w')
        c.line(16,14,17,6,'#');c.ellipse(14,3,20,9,'#');c.ellipse(15,4,19,8,'f')
        c.eye(17,5,eyes)
        c.line(15,15,19,12,'#');c.ellipse(17,9,21,14,'#');c.ellipse(18,10,20,13,'f')
        for i,hip in enumerate((7,11,15)):
            _side_leg(c,hip,18,(g+i*4)%16,floor=22,slim=True)
    return c.rows()


def walking_sprite(figure,eyes,frame):
    """Original right-facing side profiles. The native renderer mirrors left.

    Walking changes the view of the character, not just its front-facing feet.
    Idle/menu art stays unchanged. Far limbs precede the body; near limbs follow
    it. Feet stop before the lower-right badge so the signal cannot hide a step.
    """
    if figure in ('cat','crab'): return _original_profile(figure,eyes,frame)
    c=Canvas();g=frame%WALK_FRAMES;p=g//2;bob=(0,0,-1,0,0,0,-1,0)[p]
    swing=(2,1,0,-1,-2,-1,0,1)[p]
    if figure=='palm':
        # A rooted tree only sways/topples in place, never acquires a walk.
        return sprite(figure,eyes,g)
    if figure=='rooster':
        # Tail behind, beak ahead: Cooper's slim neck and long orange legs.
        _side_leg(c,19,25,(g+8)%16,bird=True)
        c.poly([(9,22),(2,18),(1,8),(4,9),(7,18)],'#')
        c.poly([(9,23),(3,23),(0,15),(3,15),(7,20)],'#')
        c.line(3,11,5,18,'b');c.line(3,17,6,21,'f')
        c.ellipse(6,16+bob,24,25+bob,'#');c.ellipse(7,17+bob,23,24+bob,'f')
        c.ellipse(10,18+bob,20,23+bob,'s');c.line(12,20+bob,17,21+bob,'b')
        c.poly([(19,21+bob),(18,11+bob),(22,10+bob),(23,21+bob)],'#')
        c.rect(19,12+bob,21,19+bob,'f')
        c.ellipse(18,5+bob,28,15+bob,'#');c.ellipse(19,6+bob,27,14+bob,'f')
        for x,y in ((19,3),(22,1),(25,3)): c.ellipse(x,y+bob,x+2,y+4+bob,'r')
        c.ellipse(25,13+bob,27,17+bob,'r')
        c.poly([(28,9+bob),(31,11+bob),(28,12+bob)],'#');c.line(28,11+bob,30,11+bob,'a')
        c.eye(24,7+bob,eyes)
        _side_leg(c,20,25,g,bird=True)
    elif figure=='rabbit':
        # Haunch drives a hop; tucked front paws and a small tail sit behind
        # a projecting muzzle. Ear movement follows the hop, not a head-on bob.
        hop=(0,0,1,2,3,4,5,5,5,4,3,2,1,0,0,0)[g];fold=(0,0,1,2,2,1,0,0)[p]
        c.ellipse(4,22,11,28,'#');c.ellipse(5,23,10,27,'b')
        c.ellipse(7,18,25,29,'#');c.ellipse(8,19,24,28,'f')
        c.ellipse(8,23,18,30,'#');c.ellipse(9,24,17,29,'s')
        extension=(3,2,0,-1,-1,0,2,3)[p]
        c.ellipse(12,28,19+extension,31,'#');c.line(14,29,18+extension,29,'f')
        c.line(23,24,23+extension//2,29,'#');c.ellipse(21,28,25,31,'#')
        c.line(22,29,24,29,'f')
        c.poly([(17,13),(13,4+fold),(15,1+fold),(19,5+fold),(21,15)],'#')
        c.line(15,5+fold,18,12,'s')
        c.ellipse(17,10,29,24,'#');c.ellipse(18,11,28,23,'f')
        c.poly([(22,14),(20,4+fold),(22,1+fold),(25,4+fold),(25,14)],'#')
        c.poly([(23,12),(22,5+fold),(23,3+fold),(24,6+fold),(24,12)],'f')
        c.line(23,5+fold,23,10,'p')
        c.ellipse(26,18,30,23,'b');c.put(30,19,'p');c.put(29,22,'#')
        c.eye(25,13,eyes);c.put(25,20,'p')
        if hop:
            rows=c.p;c=Canvas()
            for y,row in enumerate(rows):
                for x,ch in enumerate(row):
                    if ch!='.': c.put(x,y-hop,ch)
    elif figure=='robot':
        _side_leg(c,20,25,(g+8)%16,'s')
        c.rect(13,19+bob,23,25+bob,'#');c.rect(14,20+bob,22,24+bob,'s')
        c.rect(18,20+bob,22,23+bob,'f')
        c.line(16,3+bob,16,6+bob,'#');c.ellipse(14,1+bob,18,4+bob,'#');c.put(16,2+bob,'l')
        c.rect(10,6+bob,25,18+bob,'#');c.rect(12,5+bob,24,19+bob,'#')
        c.rect(11,7+bob,24,17+bob,'s');c.rect(14,6+bob,24,8+bob,'f')
        c.rect(20,9+bob,27,15+bob,'#');c.rect(21,10+bob,26,14+bob,'v')
        c.eye(23,10+bob,eyes)
        c.rect(8,10+bob,12,14+bob,'#');c.rect(9,11+bob,11,13+bob,'v')
        c.rect(19,17+bob,24,17+bob,'h');c.put(20+(p%4),17+bob,'l')
        c.poly([(15,19+bob),(18,20+bob),(18+swing,25+bob),(15+swing,25+bob)],'#')
        c.line(16,20+bob,16+swing,24+bob,'f')
        _side_leg(c,21,25,g)
    elif figure=='antenna':
        _side_leg(c,19,27,(g+8)%16,'s')
        c.line(12,8+bob,9,3+bob,'#');c.line(9,3+bob,6,2+bob,'r')
        c.line(22,8+bob,25,3+bob,'#');c.line(25,3+bob,28,2+bob,'r')
        c.ellipse(7,6+bob,27,27+bob,'#');c.ellipse(8,7+bob,26,26+bob,'s')
        c.ellipse(10,7+bob,26,24+bob,'f');c.ellipse(12,7+bob,23,13+bob,'r')
        c.ellipse(13,8+bob,17,10+bob,'p')
        c.ellipse(22,11+bob,27,18+bob,'h')
        if eyes=='shut': c.line(23,15+bob,25,15+bob,'l')
        elif eyes=='squint': c.rect(23,14+bob,25,15+bob,'l')
        else:
            c.ellipse(23,12+bob,26,15+bob,'l')
            if eyes!='wide': c.put(25 if eyes=='glance' else 24,12+bob,'w')
        c.ellipse(13+swing,18+bob,19+swing,24+bob,'#')
        c.ellipse(14+swing,19+bob,18+swing,23+bob,'f')
        _side_leg(c,20,27,g)
    elif figure=='snowman':
        roll=(0,0,1,1,0,0,-1,-1)[p];wave=(0,0,-1,-2,-2,-1,0,0)[p]
        c.ellipse(8,19,25,31,'#');c.ellipse(9,20,24,30,'s');c.ellipse(12,20,24,28,'f')
        c.line(22,21,28,18+wave,'t');c.line(28,18+wave,31,16+wave,'t')
        c.line(28,18+wave,30,19+wave,'t')
        c.ellipse(12+roll,8,26+roll,22,'#');c.ellipse(13+roll,9,25+roll,21,'f')
        c.rect(12+roll,19,25+roll,21,'g');c.line(14+roll,19,24+roll,19,'l')
        c.poly([(14,21),(17,21),(17-swing,28),(14-swing,28)],'g')
        c.eye(23+roll,12,eyes);c.poly([(27+roll,15),(31,16),(27+roll,17)],'a')
        c.put(24+roll,18,'#');c.put(23+roll,19,'#')
        c.rect(14+roll,2,24+roll,8,'#');c.rect(15+roll,3,23+roll,7,'h')
        c.rect(15+roll,7,23+roll,8,'r');c.rect(11+roll,9,27+roll,10,'#')
        c.line(12+roll,9,26+roll,9,'h');c.put(16,24,'#');c.put(16,28,'#')
    elif figure=='orb':
        roll=(0,1,2,3,4,4,3,2,1,0,-1,-2,-3,-3,-2,-1)[g]
        c.ellipse(4,3,28,31,'#');c.ellipse(5,4,27,30,'s')
        c.ellipse(8,4,27,28,'f');c.ellipse(10,5,25,24,'b')
        c.ellipse(9+roll,6,16+roll,11,'w')
        if eyes=='shut': c.line(22,16,25,16,'#')
        elif eyes=='squint': c.line(22,14,25,17,'#')
        else:
            c.ellipse(22,11,24,16,'#');c.ellipse(23,14,25,18,'#')
            if eyes!='wide': c.put(24 if eyes=='glance' else 23,12,'w')
        c.put(26,21,'#')
    else: raise ValueError(figure)
    return c.rows()


# Accessory colours are identity, never the live state. The framed badge is
# added by the native renderer and consumes the engine's mood and tint.
ACCESSORIES = {'h':'#202a3c','v':'#455d7e','r':'#bf4b58','g':'#277c60','l':'#83c58b',
               't':'#a87548','d':'#65422f','q':'#e7b879','a':'#edaa48'}

def export(skins, slots, eyes, frames):
    palettes={}
    for figure in WALKING_FIGURES:
        for name,skin in skins.items():
            palettes[f'{figure}/{name}']={ch:skin[slot] for ch,slot in slots.items() if slot!='accent'} | ACCESSORIES
            if figure == 'antenna': palettes[f'{figure}/{name}'].update(r='#fb5966', l='#45d8d1')
            if figure == 'rooster': palettes[f'{figure}/{name}']['r'] = '#b9719c'
    return {'width':SIZE,'height':SIZE,
            'sprites':{f'{fig}/{eye}/{f}':sprite(fig,eye,f) for fig in FIGURES for eye in eyes for f in range(frames)},
            'walking_frames':WALK_FRAMES,
            'walking_sprites':{f'{fig}/{eye}/{f}':walking_sprite(fig,eye,f) for fig in WALKING_FIGURES for eye in eyes for f in range(WALK_FRAMES)},
            'palettes':palettes}
