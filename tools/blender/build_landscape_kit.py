"""Создание библиотеки в отдельной сцене Blender; запуск через Blender MCP.
Масштаб: радиус игрового гекса 1, Z вверх; glTF конвертирует оси для Godot.
"""
import bpy, bmesh, math, random, json
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'art/landscape'
rng = random.Random(21112026)
scene = bpy.data.scenes.new('Civ_Landscape_Kit_v1')
bpy.context.window.scene = scene
scene.unit_settings.scale_length = 1.0
assets_collection = bpy.data.collections.new('Landscape_Assets')
scene.collection.children.link(assets_collection)
show_collection = bpy.data.collections.new('Presentation_Not_Exported')
scene.collection.children.link(show_collection)
image = bpy.data.images.load(str(OUT / 'textures/landscape_materials.png'), check_existing=True)
image.pack()
MATS = {}
RECTS = {'leaf': (0.02, 0.52), 'tropical': (0.52, 0.52), 'bark': (0.02, 0.02), 'rock': (0.52, 0.02)}

def material(kind, color=(1, 1, 1, 1)):
    key = kind + str(color)
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new('Civ_' + kind + '_' + str(len(MATS)))
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Roughness'].default_value = 0.88
    bsdf.inputs['Base Color'].default_value = color
    if kind in RECTS:
        tex = m.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image = image
        m.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    MATS[key] = m
    return m

def asset(name):
    root = bpy.data.objects.new(name, None)
    assets_collection.objects.link(root)
    root['role'] = 'landscape_asset'
    root['hex_radius'] = 1.0
    return root

def mesh(root, label, verts, faces, kind='rock', color=(1, 1, 1, 1), smooth=False):
    data = bpy.data.meshes.new(root.name + '_' + label)
    data.from_pydata(verts, [], faces)
    data.update()
    obj = bpy.data.objects.new(data.name, data)
    assets_collection.objects.link(obj)
    obj.parent = root
    obj.data.materials.append(material(kind, color))
    uv = data.uv_layers.new(name='UVMap')
    lo = [min(v[k] for v in verts) for k in range(3)]
    hi = [max(v[k] for v in verts) for k in range(3)]
    start = RECTS.get(kind, (0, 0))
    for poly in data.polygons:
        poly.use_smooth = smooth
        axes = (0, 1) if abs(poly.normal.z) > 0.55 else (0, 2)
        if abs(poly.normal.x) > 0.7:
            axes = (1, 2)
        for li in poly.loop_indices:
            p = verts[data.loops[li].vertex_index]
            uv.data[li].uv = tuple(start[d] + 0.46 * (p[a] - lo[a]) / max(0.001, hi[a] - lo[a]) for d, a in enumerate(axes))
    return obj

def tube(root, points, radii, kind='bark', sides=7, color=(1,1,1,1)):
    points = [Vector(p) for p in points]
    verts, faces = [], []
    for j, p in enumerate(points):
        direction = points[min(j+1, len(points)-1)] - points[max(j-1, 0)]
        q = direction.to_track_quat('Z', 'Y')
        for k in range(sides):
            a = k * math.tau / sides
            verts.append(tuple(p + q @ Vector((math.cos(a)*radii[j], math.sin(a)*radii[j], 0))))
    faces.append(tuple(reversed(range(sides))))
    for j in range(len(points)-1):
        for k in range(sides):
            faces.append((j*sides+k, j*sides+(k+1)%sides, (j+1)*sides+(k+1)%sides, (j+1)*sides+k))
    faces.append(tuple((len(points)-1)*sides+k for k in range(sides)))
    return mesh(root, kind, verts, faces, kind, color)

def blob(root, center, size, kind='leaf', seed=0, rough=0.18):
    r = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1)
    bm.verts.ensure_lookup_table()
    verts = []
    for v in bm.verts:
        factor = 1 + r.uniform(-rough, rough)
        verts.append(tuple(center[k] + v.co[k]*size[k]*factor for k in range(3)))
    faces = [tuple(v.index for v in f.verts) for f in bm.faces]
    bm.free()
    return mesh(root, kind, verts, faces, kind, smooth=kind in ('leaf','tropical'))

def roots(root, pos, h, radius):
    x,y,z = pos
    for k in range(5):
        a = k*math.tau/5 + .2
        tube(root, [(x+math.cos(a)*radius*2.8,y+math.sin(a)*radius*2.8,z+.002), (x,y,z+radius*2.5)], [radius*.18,radius*.55])

def broad(root, pos=(0,0,0), h=.48, seed=0, tropical=False, slender=False):
    r = random.Random(seed)
    x,y,z = pos
    trunk = .022 if slender else .035
    trunk *= h/.48
    lean = r.uniform(-.06,.06)*h
    tube(root, [(x,y,z),(x+lean,y,z+h*.42),(x+lean*.5,y+.015,z+h*.76)], [trunk,trunk*.72,trunk*.25])
    roots(root,pos,h,trunk)
    leafkind = 'tropical' if tropical else 'leaf'
    n = 8 if tropical else 7
    for k in range(n):
        a = k*2.39996 + r.uniform(-.3,.3)
        reach = h*r.uniform(.2,.34)
        level = h*r.uniform(.58,.82)
        tip = (x+math.cos(a)*reach,y+math.sin(a)*reach,z+level)
        tube(root, [(x,y,z+h*.38), (x+math.cos(a)*reach*.6,y+math.sin(a)*reach*.6,z+level*.88), tip], [trunk*.45,trunk*.28,trunk*.08])
        for j in range(3):
            c = (tip[0]+r.uniform(-.04,.04),tip[1]+r.uniform(-.04,.04),tip[2]+r.uniform(-.025,.025))
            s = h*r.uniform(.11,.17)
            blob(root,c,(s*1.1,s,s*.75),leafkind,seed*100+k*3+j,.25)
    blob(root,(x,y,z+h*.85),(h*.17,h*.16,h*.12),leafkind,seed+600,.23)

def pine(root, pos=(0,0,0), h=.52, seed=0):
    r=random.Random(seed)
    x,y,z=pos
    tube(root,[(x,y,z),(x+.006,y,z+h)], [.018*h/.52,.002])
    roots(root,pos,h,.018*h/.52)
    # Раздельные ветки и неровные игольчатые лапы вместо сплошных конусов.
    for tier in range(6):
        t=tier/6
        reach=h*(.24*(1-t)+.035)
        level=z+h*(.25+t*.62)
        n=6 if tier<3 else 5
        for k in range(n):
            a=k*math.tau/n+tier*.67+r.uniform(-.15,.15)
            tip=(x+math.cos(a)*reach,y+math.sin(a)*reach,level-.025)
            tube(root,[(x,y,level+.015),tip],[.004,.0015])
            center=(x+math.cos(a)*reach*.67,y+math.sin(a)*reach*.67,level)
            blob(root,center,(reach*.49,reach*.36,h*.05),'leaf',seed*300+tier*10+k,.3)
    blob(root,(x,y,z+h*.94),(h*.045,h*.045,h*.08),'leaf',seed+999,.15)

def frond(root, origin, angle, length, width, drop=.08, kind='tropical'):
    # Изогнутая центральная жилка с отдельными заострёнными листочками.
    o=Vector(origin); d=Vector((math.cos(angle),math.sin(angle),0)); side=Vector((-d.y,d.x,0))
    def spine(t):
        return o+d*length*t+Vector((0,0,length*.24*math.sin(math.pi*t)-drop*t*t))
    tube(root,[spine(0),spine(.5),spine(1)],[.003,.002,.0005],kind,5)
    vs,fs=[],[]
    for k in range(1,10):
        t=k/11
        c=spine(t)
        w=width*math.sin(math.pi*t)**.7
        for sign in [-1,1]:
            a=c-d*length*.045
            b=c+d*length*.035
            tip=c+side*w*sign-d*length*.1+Vector((0,0,-w*.3))
            ridge=(a+b+tip)/3+Vector((0,0,w*.07))
            base=len(vs);vs.extend([tuple(a),tuple(b),tuple(tip),tuple(ridge)])
            fs.extend([(base,base+1,base+3),(base+1,base+2,base+3),(base+2,base,base+3)])
    return mesh(root,'frond',vs,fs,kind)

def palm(root,pos=(0,0,0),h=.5,seed=0):
    r=random.Random(seed);x,y,z=pos
    bend=r.uniform(.03,.08)
    top=(x+bend,y,z+h)
    tube(root,[(x,y,z),(x+bend*.25,y,z+h*.35),top],[.023,.019,.012],sides=9)
    # Небольшие кольца и наклонённые перистые листья.
    for k in range(7):
        t=(k+1)/9
        blob(root,(x+bend*t*t,y,z+h*t),(.023,.023,.009),'bark',seed*50+k,.06)
    for k in range(9):
        frond(root,top,k*math.tau/9+r.uniform(-.1,.1),h*r.uniform(.48,.65),h*.12,h*.16)

def bush(root,pos=(0,0,0),seed=0):
    r=random.Random(seed)
    for k in range(6):
        a=k*2.399;rad=.055*math.sqrt(k)
        blob(root,(pos[0]+math.cos(a)*rad,pos[1]+math.sin(a)*rad,pos[2]+.055),(.075,.063,.065),'leaf',seed*10+k,.3)

def rock(root,pos=(0,0,0),size=(.23,.17,.18),seed=0):
    r=random.Random(seed)
    bm=bmesh.new();bmesh.ops.create_icosphere(bm,subdivisions=2,radius=1);bm.verts.ensure_lookup_table()
    vs=[]
    for v in bm.verts:
        fac=r.uniform(.8,1.17)
        zz=max(.0,(v.co.z*.5+.5)*size[2]*fac)
        vs.append((pos[0]+v.co.x*size[0]*fac,pos[1]+v.co.y*size[1]*fac,pos[2]+zz))
    fs=[tuple(v.index for v in f.verts) for f in bm.faces];bm.free()
    return mesh(root,'weathered_rock',vs,fs,'rock')

def mountain(root,seed=0,height=1.18,width=.76,snow=False):
    r=random.Random(seed);n=28;vs=[];fs=[]
    profile=[(0,1),(.13,.9),(.32,.69),(.55,.48),(.78,.25),(.94,.08)]
    ridge=[r.uniform(.77,1.18) for k in range(n)]
    for j,(z,rad) in enumerate(profile):
        for k in range(n):
            a=math.tau*k/n
            rr=width*rad*ridge[k]*(1+.10*math.sin(k*3.0+j*.7))
            # Скальные ребра сохраняют направление вверх по склону.
            zz=height*z+(0 if j==0 else r.uniform(-.045,.045)*height)
            vs.append((math.cos(a)*rr+.12*z,math.sin(a)*rr*.8-.08*z,zz))
    for j in range(len(profile)-1):
        for k in range(n):
            a=j*n+k;b=j*n+(k+1)%n;c=(j+1)*n+(k+1)%n;d=(j+1)*n+k
            fs.extend([(a,b,c),(a,c,d)])
    vs.append((.12,-.08,height));top=len(vs)-1
    for k in range(n):fs.append(((len(profile)-1)*n+k,(len(profile)-1)*n+(k+1)%n,top))
    fs.append(tuple(reversed(range(n))))
    ob=mesh(root,'ridged_peak',vs,fs,'rock')
    if snow:
        snowmat=material('snow',(.82,.88,.89,1));ob.data.materials.append(snowmat)
        for poly in ob.data.polygons:
            if poly.center.z>height*.68 and poly.normal.z>.15:poly.material_index=1
    for k in range(12):
        a=r.uniform(0,math.tau);rad=r.uniform(width*.65,width*.96)
        rock(root,(math.cos(a)*rad,math.sin(a)*rad*.8,0),(.07,.05,r.uniform(.035,.12)),seed*30+k)
    for k in range(5):
        a=k*math.tau/5+.3;rad=width*.88
        bush(root,(math.cos(a)*rad,math.sin(a)*rad*.8,0),seed*5+k)

ASSETS=[]
def make(name,fn):
    root=asset(name);fn(root);ASSETS.append(root);return root

make('tree_oak_a',lambda a:broad(a,seed=11))
make('tree_oak_b',lambda a:broad(a,h=.42,seed=23))
make('tree_birch_a',lambda a:broad(a,h=.51,seed=51,slender=True))
make('tree_pine_a',lambda a:pine(a,seed=17))
make('tree_pine_b',lambda a:pine(a,h=.44,seed=29))
make('tree_palm_a',lambda a:palm(a,seed=37))
make('tree_palm_b',lambda a:palm(a,h=.43,seed=91))
make('tree_jungle_a',lambda a:broad(a,h=.48,seed=61,tropical=True))
make('shrub_a',lambda a:bush(a,seed=42))
make('fern_a',lambda a:[frond(a,(0,0,.03),k*math.tau/9,.19,.055,.035) for k in range(9)])

def reeds(root):
    r=random.Random(991)
    for k in range(22):
        x,y=r.uniform(-.14,.14),r.uniform(-.12,.12);h=r.uniform(.10,.22)
        tube(root,[(x,y,0),(x+.015,y+.005,h)], [.002,.001], 'stem',5,(.22,.34,.12,1))
        frond(root,(x,y,h*.25),r.uniform(0,math.tau),h*.6,.014,.015,'leaf')
        if k%3==0:blob(root,(x+.013,y+.004,h*.91),(.009,.009,.025),'bark',k)
make('reeds_a',reeds)
make('boulder_a',lambda a:rock(a,seed=5))
make('boulders_cluster_a',lambda a:[rock(a,(math.cos(k*2.4)*.18,math.sin(k*2.4)*.14,0),(.12,.09,.10+k*.025),60+k) for k in range(5)])

def cliff(root):
    for k in range(5):
        rock(root,((k-2)*.24,0,-.02),(.18,.22,.35+(k%3)*.08),812+k)
    for k in range(7):rock(root,((k-3)*.16,-.2,0),(.07,.08,.045),900+k)
make('cliff_segment_a',cliff)
make('mountain_peak_a',lambda a:mountain(a,seed=43))
make('mountain_peak_b',lambda a:mountain(a,seed=81,height=.95,width=.8))
make('mountain_snow_a',lambda a:mountain(a,seed=95,height=1.25,snow=True))

def ridge(root):
    mountain(root,seed=76,height=.78,width=.54)
    # Второй пик смещён, но весь объект остаётся в пределах гекса радиуса 1.
    before=set(root.children)
    mountain(root,seed=77,height=.65,width=.43)
    for ob in set(root.children)-before:
        for v in ob.data.vertices:v.co.x+=.44;v.co.y+=.12
make('mountain_ridge_a',ridge)

def hill(root):
    # Низкое каменистое возвышение с травянистыми островками.
    rock(root,(0,0,0),(.69,.52,.25),108)
    for k in range(5):bush(root,(math.cos(k*2.4)*.43,math.sin(k*2.4)*.31,.08),700+k)
make('rocky_hill_a',hill)

def log(root):
    tube(root,[(-.25,0,.055),(0,.015,.06),(.24,.0,.045)],[.06,.055,.04],sides=12)
    tube(root,[(-.07,.01,.07),(.015,.15,.12)],[.025,.008])
    for k in range(3):bush(root,(-.23+k*.2,.09,0),510+k)
make('fallen_log_a',log)

def forest(root,seed,style):
    r=random.Random(seed)
    count=9 if style=='jungle' else 11
    for k in range(count):
        a=k*2.39996+seed;rad=.70*math.sqrt((k+.5)/count)
        pos=(math.cos(a)*rad,math.sin(a)*rad,0)
        h=r.uniform(.25,.39)
        if style=='jungle':
            if k%3==0:palm(root,pos,h,seed+k)
            else:broad(root,pos,h,seed+k,True)
        elif style=='conifer' or k%3!=0:pine(root,pos,h,seed+k)
        else:broad(root,pos,h*.92,seed+k)
    for k in range(5):
        a=k*2.4+.6;bush(root,(math.cos(a)*.62,math.sin(a)*.62,0),seed*4+k)
    for k in range(4):
        a=k*2.1;rock(root,(math.cos(a)*.7,math.sin(a)*.7,0),(.04,.035,.04),seed+k)
make('forest_mixed_tile_a',lambda a:forest(a,201,'mixed'))
make('forest_mixed_tile_b',lambda a:forest(a,301,'mixed'))
make('forest_conifer_tile_a',lambda a:forest(a,401,'conifer'))
make('jungle_tile_a',lambda a:forest(a,501,'jungle'))
make('jungle_tile_b',lambda a:forest(a,601,'jungle'))

# Сводим каждую модель в один редактируемый меш с несколькими материалами.
# Каждый экспорт будет содержать только один корень и один меш, без презентации.
for root in ASSETS:
    children=list(root.children)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in children:ob.select_set(True)
    bpy.context.view_layer.objects.active=children[0]
    if len(children)>1:
        bpy.ops.object.join()
    joined=bpy.context.object
    joined.name=root.name+'_mesh'
    # Нормали исправлены без модификаторов, UV и материалы остаются редактируемыми.
    bm=bmesh.new();bm.from_mesh(joined.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(joined.data);bm.free()
    joined.data.validate(verbose=False, clean_customdata=True)
    joined.data.update()

for i, root in enumerate(ASSETS):
    root.location=((i%5-2)*2.6,(2-i//5)*2.6,0)

print('CREATED',len(ASSETS),'assets', 'meshes',sum(len(a.children) for a in ASSETS))
