"""Превью, исходник .blend, облегчённые glTF с общей текстурой и каталог моделей."""
import bpy, math, json, io_scene_gltf2
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'art/landscape'
scene=bpy.context.scene
roots=[o for o in scene.objects if o.get('role')=='landscape_asset']
show=bpy.data.collections['Presentation_Not_Exported']

def solid(name,color):
    m=bpy.data.materials.new(name);m.use_nodes=True
    bsdf=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value=(*color,1)
    bsdf.inputs['Roughness'].default_value=.9
    return m

ground=solid('Gallery_Soil',(.12,.16,.10))
labelmat=solid('Gallery_Lettering',(.73,.77,.64))
floor=solid('Gallery_Backdrop',(.055,.073,.08))
for root in roots:
    bpy.ops.mesh.primitive_cylinder_add(vertices=6,radius=.98,depth=.025,location=(*root.location[:2],-.018))
    p=bpy.context.object;p.name='Display_Base_'+root.name
    for c in list(p.users_collection):c.objects.unlink(p)
    show.objects.link(p);p.data.materials.append(ground)
    curve=bpy.data.curves.new('Label','FONT');curve.body=root.name.replace('_',' ')
    curve.size=.12;curve.align_x='CENTER'
    obj=bpy.data.objects.new('Label_'+root.name,curve);show.objects.link(obj)
    obj.location=(root.location.x,root.location.y-1.10,.002)
    curve.materials.append(labelmat)

bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.04))
obj=bpy.context.object;obj.name='Gallery_Backdrop'
for c in list(obj.users_collection):c.objects.unlink(obj)
show.objects.link(obj);obj.data.materials.append(floor)

world=bpy.data.worlds.new('Landscape_Studio_World');world.use_nodes=True
background=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND')
background.inputs['Color'].default_value=(.32,.39,.48,1)
background.inputs['Strength'].default_value=.5
scene.world=world

def light(name,kind,location,energy,size=None):
    data=bpy.data.lights.new(name,kind);data.energy=energy
    ob=bpy.data.objects.new(name,data);show.objects.link(ob);ob.location=location
    ob.rotation_euler=(Vector((0,0,0))-ob.location).to_track_quat('-Z','Y').to_euler()
    if size is not None:data.size=size
    return ob
light('Key_Softbox','AREA',(1,-4,10),1700,7)
light('Fill_Softbox','AREA',(-5,2,7),900,8)
sun=light('Daylight','SUN',(3,-5,8),1.6);sun.data.angle=math.radians(18)

data=bpy.data.cameras.new('Landscape_Kit_Camera')
camera=bpy.data.objects.new(data.name,data);show.objects.link(camera);scene.camera=camera
data.type='ORTHO';data.lens=45;data.clip_end=300

def aim(center,span):
    center=Vector(center);camera.location=center+Vector((span*.6,-span*.82,span*.95))
    camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale=span

scene.render.resolution_x=1700;scene.render.resolution_y=1500;scene.render.resolution_percentage=100
png=next(i.identifier for i in bpy.types.ImageFormatSettings.bl_rna.properties['file_format'].enum_items if i.identifier.endswith('PNG'))
scene.render.image_settings.file_format=png
scene.render.film_transparent=False
aim((0,0,.15),18)

# Сохраняем копию библиотеки, не перезаписывая файл исходной пользовательской сцены.
source_path=OUT/'source/landscape_kit_v1.blend'
if source_path.exists():
    raise RuntimeError('Исходник уже существует; выберите новое имя версии перед повторным экспортом')
bpy.ops.wm.save_as_mainfile(filepath=str(source_path),compress=True,copy=True)

def render(path,center,span,selected=None,resolution=(1500,1100)):
    previous={o:o.hide_render for o in scene.objects}
    if selected is not None:
        allowed=set(selected)
        for root in roots:
            for child in root.children:child.hide_render=root.name not in allowed
        for ob in show.objects:
            if ob.name.startswith(('Label_','Display_Base_')):
                ob.hide_render=not any(ob.name.endswith(name) for name in allowed)
    aim(center,span)
    scene.render.resolution_x,scene.render.resolution_y=resolution
    scene.render.filepath=str(path)
    bpy.ops.render.render(write_still=True)
    for ob,value in previous.items():ob.hide_render=value

render(OUT/'previews/library_overview.png',(0,0,.15),18,resolution=(1700,1500))
forest=next(a for a in roots if a.name=='forest_mixed_tile_a')
render(OUT/'previews/forest_closeup.png',forest.location+Vector((0,0,.15)),2.4,[forest.name])
jungle=next(a for a in roots if a.name=='jungle_tile_a')
render(OUT/'previews/jungle_closeup.png',jungle.location+Vector((0,0,.16)),2.4,[jungle.name])
peak=next(a for a in roots if a.name=='mountain_peak_a')
render(OUT/'previews/mountain_closeup.png',peak.location+Vector((0,0,.45)),2.6,[peak.name])

# Enum списка форматов у оператора динамический; берём действительное значение из addon API.
items=io_scene_gltf2.get_format_items(None,bpy.context)
fmt=next(item[0] for item in items if 'Separate' in item[1])
export_collection=bpy.data.collections.new('Temporary_Export')
scene.collection.children.link(export_collection)
catalog=[]
for root in roots:
    original=root.children[0]
    obj=original.copy();obj.data=original.data.copy();export_collection.objects.link(obj)
    obj.parent=None;obj.matrix_world=original.matrix_local.copy();obj.name=root.name+'_game'
    src_tris=sum(len(p.vertices)-2 for p in obj.data.polygons)
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    ratio=.28 if 'tile_' in root.name else (.55 if root.name.startswith('tree_') else .72)
    if src_tris>1000:
        mod=obj.modifiers.new('Game_Mesh_Simplification','DECIMATE');mod.ratio=ratio
        bpy.ops.object.modifier_apply(modifier=mod.name)
    mesh=obj.data
    mesh.validate(verbose=False,clean_customdata=True)
    mesh.update()
    export_tris=sum(len(p.vertices)-2 for p in mesh.polygons)
    bounds=[Vector(c) for c in obj.bound_box]
    lo=[min(c[k] for c in bounds) for k in range(3)];hi=[max(c[k] for c in bounds) for k in range(3)]
    filepath=OUT/'models'/f'{root.name}.gltf'
    bpy.ops.export_scene.gltf(filepath=str(filepath),export_format=fmt,use_selection=True,
        export_texture_dir='../textures',export_animations=False,export_cameras=False,export_lights=False)
    catalog.append({'id':root.name,'file':'models/'+root.name+'.gltf','source_triangles':src_tris,
        'export_triangles':export_tris,'bounds_blender_z_up':{'min':lo,'max':hi},
        'purpose':'tile_cluster' if 'tile_' in root.name else 'individual_object'})
    bpy.data.objects.remove(obj,do_unlink=True)
    bpy.data.meshes.remove(mesh)
bpy.data.collections.remove(export_collection)
(OUT/'catalog.json').write_text(json.dumps({'hex_radius':1.0,'source':'source/landscape_kit_v1.blend',
    'assets':catalog},indent=2),encoding='utf-8')
aim((0,0,.15),18)
scene.render.resolution_x=1700;scene.render.resolution_y=1500
print('EXPORTED',len(catalog),'models. Source triangles:',sum(a['source_triangles'] for a in catalog),
      'game triangles:',sum(a['export_triangles'] for a in catalog))
