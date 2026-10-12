"""Detailed 32px companions. Small menu-bar sprites remain in mascot.py.

Parts move independently on an eight-frame clock; the grounded body never bobs.
These are original pixel drawings inspired by the supplied character references.
"""
from math import sin, pi

WALK_FRAMES = 16

SIZE = 32
FIGURES = ('robot', 'rooster', 'rabbit', 'snowman', 'palm', 'orb', 'antenna', 'pup', 'rex')

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
    def dot_eye(self,x,y,eyes):
        if eyes=='shut': self.line(x,y+1,x+1,y+1,'#')
        elif eyes=='squint': self.rect(x,y+1,x+1,y+1,'#')
        else:
            self.rect(x,y,x+1,y+1,'#')
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
    elif figure=='pup':
        # Dopey charge: floppy ears, a red bandana, one tooth, tongue out.
        flap=(0,0,1,2,2,1,0,0)[f];bark=(0,0,1,2,2,1,0,0)[f]
        c.rect(3,8,8,19,'#');c.rect(4,9,7,18,'f');c.rect(5,11,6,17,'p')
        c.rect(23,7+flap,28,18+flap,'#');c.rect(24,8+flap,27,17+flap,'f');c.rect(25,10+flap,26,16+flap,'p')
        c.rect(8,5,23,18,'#');c.rect(9,6,22,17,'f');c.rect(11,4,20,6,'#');c.rect(12,5,19,6,'f')
        c.line(10,9,13,10,'#');c.line(18,10,21,9,'#')
        c.dot_eye(11,11,eyes);c.dot_eye(18,11,eyes)
        c.put(10,15,'p');c.put(21,15,'p');c.rect(14,14,17,15,'#')
        c.rect(13,16,18,16+bark,'#');c.put(16,16,'w');c.rect(14,17,17,17+bark,'p')
        c.rect(9,18,23,20,'#');c.rect(10,18,22,19,'r')
        c.rect(9,20,23,26,'#');c.rect(10,21,22,25,'f');c.rect(12,22,20,25,'s')
        c.rect(10,26,14,31,'#');c.rect(11,27,13,30,'f');c.rect(9,30,15,31,'#')
        c.rect(18,26,22,31,'#');c.rect(19,27,21,30,'f');c.rect(17,30,23,31,'#')
    elif figure=='rex':
        # Vacant eyes, angry brows, a snap, and arms that cannot reach the mouth.
        snap=(0,0,1,2,3,2,1,0)[f];arm=(0,1,2,1,0,-1,0,1)[f]
        c.rect(10,22,15,31,'#');c.rect(11,23,14,30,'f');c.rect(9,29,15,31,'#')
        c.rect(17,22,22,31,'#');c.rect(18,23,21,30,'f');c.rect(17,29,23,31,'#')
        c.rect(8,16,24,24,'#');c.rect(9,17,23,23,'f');c.rect(12,19,20,23,'b')
        c.rect(2,17+arm,7,21+arm,'#');c.rect(3,18+arm,6,20+arm,'f');c.put(2,21+arm,'#');c.put(4,22+arm,'#')
        c.rect(25,17-arm,30,21-arm,'#');c.rect(26,18-arm,29,20-arm,'f');c.put(28,22-arm,'#');c.put(30,21-arm,'#')
        c.rect(5,2,27,15,'#');c.rect(6,3,26,14,'f');c.rect(8,1,24,4,'#');c.rect(9,2,23,3,'f')
        c.line(9,6,13,7,'#');c.line(19,7,23,6,'#')
        c.dot_eye(10,7,eyes);c.dot_eye(19,8,eyes)
        c.put(9,11,'p');c.put(22,11,'p')
        c.rect(12,12,21,14,'#');c.put(15,13,'w')
        c.rect(11,14,22,15+snap,'#');c.rect(12,15,21,15+snap,'f')
        if snap: c.rect(14,15,18,14+snap,'p')
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

def _side_leg(c, hip, top, phase, fill='f', bird=False, floor=31, slim=False, width=1):
    # `width` thickens the fill, not the outline: a heavy leg is one stroke
    # several pixels wide. Two thin legs drawn side by side left a dark seam
    # down the middle of each.
    toe,ground=foot_pose(hip,phase,floor)
    knee=hip+STRIDE[phase % WALK_FRAMES]//2
    knee_y=min(top+2,ground-1)
    if bird:
        c.line(hip,top,knee,knee_y,'a');c.line(knee,knee_y,toe,ground,'a')
        c.line(toe-1,ground,toe+1,ground,'a')
    else:
        for dx in ((0,) if slim else range(-1,width+1)):
            c.line(hip+dx,top,knee+dx,knee_y,'#')
            c.line(knee+dx,knee_y,toe+dx,ground-1,'#')
        for dx in range(width):
            c.line(hip+dx,top,knee+dx,knee_y,fill);c.line(knee+dx,knee_y,toe+dx,ground-1,fill)
        c.rect(toe-1,ground-1,toe+width,ground,'#')
        c.line(toe,ground-1,toe+width-1,ground-1,fill)

def _mini_eye(c,x,y,eyes):
    if eyes=='shut': c.line(x,y+1,x+1,y+1,'#')
    elif eyes=='squint': c.rect(x,y,x+1,y,'#')
    else:
        c.rect(x,y,x+1,y+1,'#')
        if eyes!='wide': c.put(x+(1 if eyes=='glance' else 0),y,'w')

def _original_profile(figure,eyes,phase):
    # The original characters keep their original 22x23 pixel grid. No size
    # or outline-weight jump when the front portrait becomes a profile.
    c=Canvas(22,23);g=phase%WALK_FRAMES
    if figure=='cat':
        _side_leg(c,6,16,(g+8)%16,'s',floor=22,slim=True)
        c.poly([(7,15),(2,12),(1,6),(3,4),(5,8),(6,14)],'#')
        c.poly([(6,14),(3,11),(2,7),(4,6),(5,12)],'s')
        c.ellipse(4,12,15,20,'#');c.ellipse(5,13,14,19,'f');c.ellipse(6,15,12,19,'b')
        c.poly([(11,8),(13,1),(16,8)],'#');c.poly([(13,6),(14,3),(15,6)],'p')
        c.ellipse(10,5,19,14,'#');c.ellipse(11,6,18,13,'f')
        c.ellipse(15,9,21,15,'#');c.ellipse(16,10,20,14,'b');c.put(21,11,'p')
        _mini_eye(c,15,7,eyes)
        _side_leg(c,8,16,g,floor=22,slim=True)
        _side_leg(c,13,16,(g+8)%16,floor=22,slim=True)
    else:
        for i,hip in enumerate((4,8,12)):
            _side_leg(c,hip,16,(g+8+i*5)%16,'s',floor=22,slim=True)
        c.ellipse(3,11,15,19,'#');c.ellipse(4,12,14,18,'f');c.line(6,14,12,14,'w')
        c.line(13,12,16,6,'#');c.ellipse(15,3,20,8,'#');c.ellipse(16,4,19,7,'f')
        _mini_eye(c,17,4,eyes)
        c.ellipse(13,8,21,15,'#');c.ellipse(14,9,20,14,'f');c.line(15,11,19,12,'w')
        for i,hip in enumerate((5,9,13)):
            _side_leg(c,hip,16,(g+i*5)%16,floor=22,slim=True)
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
        # A rooted tree only sways in place, never acquires a walk.
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
        # Hop compresses the haunch and lags the ears. The back paw stays on the floor.
        hop=(0,0,1,1,2,2,3,2,2,1,1,0,0,0,0,0)[g]
        lag=(0,0,0,1,1,2,2,3,2,2,1,0,0,0,0,0)[g]
        reach=(0,1,2,3,3,2,1,0,-1,-2,-2,-1,0,1,0,0)[g]
        y=lambda n: n-hop
        c.ellipse(3,y(22),9,y(28),'#');c.ellipse(4,y(23),8,y(27),'b')
        c.ellipse(6,y(16),22,y(27),'#');c.ellipse(7,y(17),21,y(26),'f')
        c.ellipse(7,y(21),16,y(29),'#');c.ellipse(8,y(22),15,y(28),'s')
        c.rect(8,y(27),14,31,'#');c.rect(9,y(28),13,30,'f')
        # Ears first, so the head covers their roots. Tips lean back as the hop rises.
        bx=15-lag
        c.rect(bx,y(3),bx+3,y(14),'#');c.rect(bx+1,y(4),bx+2,y(13),'p')
        c.rect(bx+3,y(2),bx+6,y(14),'#');c.rect(bx+4,y(3),bx+5,y(13),'f')
        c.line(bx+4,y(4),bx+4,y(12),'p')
        c.ellipse(16,y(10),27,y(20),'#');c.ellipse(17,y(11),26,y(19),'f')
        c.ellipse(23,y(14),30,y(19),'b');c.put(29,y(15),'p');c.put(25,y(16),'p')
        c.eye(22,y(12),eyes)
        fx=16+reach;paw=hop if reach>0 else 0
        c.rect(fx,y(25),fx+5,30-paw,'#');c.rect(fx+1,y(26),fx+4,29-paw,'f')
        c.rect(fx,30-paw,fx+6,31-paw,'#')
    elif figure=='robot':
        # Narrow chassis, one pod behind, visor on the leading face.
        _side_leg(c,16,24,(g+8)%16,'s')
        c.rect(14,18,23,25,'#');c.rect(15,19,22,24,'s');c.rect(17,19,22,23,'f')
        c.poly([(20,19),(23,18),(24+swing,25),(20+swing,25)],'#')
        c.line(22,20,22+swing,24,'f')
        c.rect(8,10,14,16,'#');c.rect(9,11,13,15,'v')
        c.rect(12,5,23,17,'#');c.rect(13,6,21,16,'f');c.rect(14,6,20,8,'s')
        c.line(17,1,17,5,'#');c.ellipse(15,0,19,3,'#');c.put(17,1,'l')
        c.rect(19,7,27,16,'#');c.rect(20,8,26,15,'v')
        c.eye(21,9,eyes);c.put(22,15,'l')
        _side_leg(c,19,24,g)
    elif figure=='antenna':
        # One antenna and one arm lead; the far pair tuck behind the round body.
        _side_leg(c,16,26,(g+8)%16,'s',slim=True)
        c.line(11,12,8,7,'#');c.put(7,6,'r')
        c.ellipse(9,8,25,26,'#');c.ellipse(10,9,24,25,'s');c.ellipse(12,9,24,23,'f')
        c.ellipse(16,9,23,14,'r')
        c.line(20,9,24,3,'#');c.line(24,3,27,2,'r')
        c.ellipse(19,12,25,18,'h')
        if eyes=='shut': c.line(21,15,23,15,'l')
        elif eyes=='squint': c.rect(21,14,23,15,'l')
        else:
            c.ellipse(20,12,24,16,'l')
            if eyes!='wide': c.put(23 if eyes=='glance' else 21,13,'w')
        c.ellipse(6,16,11,21,'#');c.ellipse(7,17,10,20,'f')
        c.ellipse(22+swing,17,28+swing,23,'#');c.ellipse(23+swing,18,27+swing,22,'f')
        _side_leg(c,19,26,g,slim=True)
    elif figure=='snowman':
        # Profile hat, carrot leading, scarf trailing. The bottom ball stays planted.
        lean=(0,1,1,0,-1,-1,0,1)[p];wave=(0,-1,-2,-1,0,1,2,1)[p]
        c.ellipse(8,20,24,31,'#');c.ellipse(9,21,23,30,'s');c.ellipse(12,21,22,28,'f')
        c.put(18,24,'#');c.put(18,28,'#')
        c.line(10,22,2,26+wave,'t');c.line(4,24+wave,1,22+wave,'t')
        c.ellipse(12+lean,8,24+lean,21,'#');c.ellipse(13+lean,9,23+lean,20,'f')
        c.rect(13+lean,17,23+lean,19,'g');c.line(14+lean,17,22+lean,17,'l')
        c.poly([(12+lean,18),(8+lean,18),(4-swing,26),(8-swing,26)],'g')
        c.eye(20+lean,11,eyes)
        c.poly([(23+lean,13),(31,14),(23+lean,16)],'a');c.put(23+lean,14,'q')
        c.rect(15+lean,2,22+lean,7,'#');c.rect(16+lean,3,21+lean,6,'h')
        c.rect(16+lean,6,21+lean,7,'r');c.rect(11+lean,8,26+lean,9,'#');c.line(12+lean,8,25+lean,8,'h')
        c.line(22,22,28,18+wave,'t');c.line(28,18+wave,30,16+wave,'t')
    elif figure=='orb':
        # Same pearl and diagonal eyes. The highlight and the gaze travel with the roll.
        squash=(0,0,1,1,2,1,0,0,1,1,2,1,0,0,1,0)[g]
        lead=(0,0,1,1,2,2,2,1,1,0,0,0,1,1,0,0)[g]
        c.ellipse(5-squash,4+squash,27+squash,31,'#')
        c.ellipse(6-squash,5+squash,26+squash,30,'s')
        c.ellipse(7-squash,5+squash,25+squash,28,'f')
        c.ellipse(9,6+squash,22,22,'b')
        hx=(4,6,8,11,14,17,19,17,14,11,8,6,5,4,5,4)[g]
        c.ellipse(hx,6,hx+7,12,'w')
        ex,ey=17+lead,12
        if eyes=='shut': c.line(ex,ey+4,ex+4,ey+4,'#')
        elif eyes=='squint': c.line(ex,ey+1,ex+4,ey+5,'#')
        else:
            c.ellipse(ex,ey,ex+3,ey+5,'#');c.ellipse(ex+2,ey+3,ex+5,ey+8,'#')
            if eyes!='wide': c.put(ex+(2 if eyes=='glance' else 1),ey+1,'w')
    elif figure=='pup':
        # A trot: diagonal legs move together on the shared planted-foot gait,
        # so no paw slides while the window travels. The tail wags and the ear
        # swings a beat behind; neither changes length.
        wag=(0,1,2,1,0,-1,-2,-1)[p];ear=(0,0,1,1,0,0,-1,-1)[(p+1)%8]
        _side_leg(c,9,23,(g+8)%16,'s');_side_leg(c,18,23,g,'s')
        c.poly([(9,19),(4,13+wag),(3,11+wag),(5,11+wag),(10,17)],'#')
        c.poly([(9,18),(5,13+wag),(4,12+wag),(9,17)],'f')
        c.ellipse(6,16,22,26,'#');c.ellipse(7,17,21,25,'f')
        _side_leg(c,10,23,g);_side_leg(c,19,23,(g+8)%16)
        c.ellipse(15,6,25,17,'#');c.ellipse(16,7,24,16,'f')
        c.rect(23,10,30,15,'#');c.rect(24,11,29,14,'f')
        c.rect(28,11,30,12,'#');c.put(27,14,'w');c.rect(25,15,27,16,'p')
        c.line(18,8,21,9,'#');c.dot_eye(20,10,eyes)
        c.rect(15+ear,8,18+ear,17,'#');c.rect(16+ear,9,17+ear,16,'f');c.line(16+ear,10,16+ear,15,'p')
        c.rect(15,16,23,18,'#');c.rect(16,17,22,17,'r');c.rect(13,17,15,19,'#');c.put(14,18,'r')
    elif figure=='rex':
        # A stomp: the body drops as each foot lands and the heavy head lands a
        # frame later. Both feet use the shared planted-foot gait; the arm is
        # too short to reach anything, and the jaw snaps once a stride.
        dip=1 if g in (0,1,8,9) else 0
        nod=1 if g in (1,2,9,10) else 0
        bite=(0,0,0,0,1,2,2,1,0,0,0,0,0,0,0,0)[g]
        sway=(0,1,1,0,0,-1,-1,0)[p]
        # Legs two pixels thick: a rex's, not a bird's, on the same gait.
        _side_leg(c,11,24,(g+8)%16,'s',width=2)
        c.poly([(10,23+dip),(1,18+sway),(0,15+sway),(2,15+sway),(10,18+dip)],'#')
        c.poly([(10,22+dip),(2,17+sway),(2,16+sway),(10,19+dip)],'f')
        c.ellipse(8,14+dip,22,26,'#');c.ellipse(9,15+dip,21,25,'f');c.ellipse(14,18+dip,20,25,'b')
        _side_leg(c,15,24,g,width=2)
        y=nod
        c.rect(14,4+y,28,16+y,'#');c.rect(15,5+y,27,15+y,'f')
        c.line(16,6+y,20,7+y,'#');c.dot_eye(22,7+y,eyes)
        c.rect(24,10+y,31,14+y,'#');c.rect(25,11+y,30,13+y,'f');c.put(28,12+y,'w')
        c.rect(22,14+y,30,16+y+bite,'#');c.rect(23,15+y,29,15+y+bite,'f')
        if bite: c.rect(25,15+y,28,14+y+bite,'p')
        c.rect(20,17+dip,23,19+dip,'#');c.put(21,18+dip,'f');c.put(23,20+dip,'#')
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
