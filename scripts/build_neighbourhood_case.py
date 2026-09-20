#!/usr/bin/env python3
"""Build the public case from OSM vector data, never Google imagery.

First import: python3 scripts/build_neighbourhood_case.py --osm /path/export.osm
Rebuild: python3 scripts/build_neighbourhood_case.py
The distributed source and derived geometry databases are ODbL 1.0.
"""
import argparse
import hashlib
import json
import math
import random
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "frontend/public/cases/springer-park"
LAT, LON = 49.2660712, -122.9895463
WIDTH, DEPTH, SCALE = 440, 290, 25 / 7
NOTICE = "© OpenStreetMap contributors · ODbL 1.0"
LICENSE = "https://opendatacommons.org/licenses/odbl/1-0/"
SOURCE = "https://www.openstreetmap.org/copyright"


def xy(lon, lat):
    return [(lon-LON)*111320*math.cos(math.radians(LAT)), -(lat-LAT)*111320]


def tags(element):
    return {t.attrib["k"]: t.attrib["v"] for t in element.findall("tag")}


def read_osm(path):
    root = ET.parse(path).getroot()
    nodes = {n.attrib["id"]: xy(float(n.attrib["lon"]), float(n.attrib["lat"])) for n in root.findall("node")}
    features = []
    for way in root.findall("way"):
        t = tags(way)
        kind = "building" if "building" in t else "road" if "highway" in t else "land" if t.get("leisure") in ("park", "garden", "playground", "swimming_pool") else None
        if kind is None:
            continue
        points = [nodes[n.attrib["ref"]] for n in way.findall("nd") if n.attrib["ref"] in nodes]
        if len(points) < 2:
            continue
        if kind != "road" and (len(points) < 4 or points[0] != points[-1]):
            continue
        if kind == "building" and not all(abs(x) < WIDTH/2 and abs(z) < DEPTH/2 for x,z in points):
            continue
        if not any(abs(x) < WIDTH/2 and abs(z) < DEPTH/2 for x,z in points):
            continue
        features.append({"osm_way_id": way.attrib["id"], "kind": kind, "points": [[round(x,3),round(z,3)] for x,z in points], "tags": {k:v for k,v in t.items() if k in ("name", "building", "building:levels", "height", "highway", "leisure")}})
    return {"attribution": NOTICE, "license": LICENSE, "source": SOURCE, "retrieved": "2026-09-20", "origin": [LON,LAT], "projection": "Local equirectangular metres; X east, Z south", "features": features}


def inside(x,z,poly):
    odd = False
    for a,b in zip(poly,poly[1:]+poly[:1]):
        if (a[1]>z)!=(b[1]>z) and x < (b[0]-a[0])*(z-a[1])/(b[1]-a[1])+a[0]:
            odd = not odd
    return odd


def clip(a,b):
    dx,dz=b[0]-a[0],b[1]-a[1]
    lo,hi=0.,1.
    for p,q in [(-dx,a[0]+WIDTH/2),(dx,WIDTH/2-a[0]),(-dz,a[1]+DEPTH/2),(dz,DEPTH/2-a[1])]:
        if abs(p)<1e-9:
            if q<0:return None
        elif p<0:lo=max(lo,q/p)
        else:hi=min(hi,q/p)
    if lo>hi:return None
    return ([a[0]+lo*dx,a[1]+lo*dz],[a[0]+hi*dx,a[1]+hi*dz])


def build(data):
    parts=[]
    def part(group,name,p,size,color,material="concrete",yaw=0,shape="block",collide=True,alpha=0,cls=None):
        item={"id":f"p{len(parts):05}","source_id":group,"group":group,"name":name,"shape":shape,"position":[round(v*SCALE,4) for v in p],"size":[round(max(.015,v)*SCALE,4) for v in size],"rotation":[0,round(yaw,4),0],"material":material,"color":color,"transparency":alpha,"collidable":collide,"cast_shadow":alpha<.8}
        if cls:item["class"]=cls
        parts.append(item)
    def segment(group,a,b,width,y,height,color,material="concrete",name="Segment"):
        dx,dz=b[0]-a[0],b[1]-a[1]
        length=math.hypot(dx,dz)
        if length<.05:return
        part(group,name,[(a[0]+b[0])/2,y,(a[1]+b[1])/2],[length,height,width],color,material,-math.degrees(math.atan2(dz,dx)))
    def fill(group,poly,top,height,color,material):
        zs=[p[1] for p in poly];low,high=max(min(zs),-DEPTH/2),min(max(zs),DEPTH/2)
        count=max(1,min(80,math.ceil((high-low)/1.4)));step=(high-low)/count
        if step<=0:return
        for i in range(count):
            z=low+(i+.5)*step
            hits=sorted(a[0]+(z-a[1])*(b[0]-a[0])/(b[1]-a[1]) for a,b in zip(poly,poly[1:]+poly[:1]) if (a[1]<=z<b[1]) or (b[1]<=z<a[1]))
            for left,right in zip(hits[::2],hits[1::2]):
                left,right=max(left,-WIDTH/2),min(right,WIDTH/2)
                if right>left:part(group,"Polygon mass",[(left+right)/2,top-height/2,z],[right-left,height,step],color,material)
    part("site","Ground",[0,-1,0],[WIDTH,2,DEPTH],"#a4b68c","grass")
    buildings=[f for f in data["features"] if f["kind"]=="building"]
    roads=[]
    for f in data["features"]:
        if f["kind"]=="land":
            kind=f["tags"]["leisure"]
            fill("land_"+f["osm_way_id"],f["points"],.05,.1,"#7cacbe" if kind=="swimming_pool" else "#d4bd8c" if kind=="playground" else "#87a572","water" if kind=="swimming_pool" else "grass")
    for f in data["features"]:
        if f["kind"]!="road":continue
        kind=f["tags"]["highway"]
        width={"primary":10,"secondary":9,"tertiary":8,"residential":6,"service":4,"footway":1.65,"path":1.7,"cycleway":2.2,"steps":1.8}.get(kind,4)
        walking=kind in ("footway","path","steps","cycleway")
        for a,b in zip(f["points"],f["points"][1:]):
            clipped=clip(a,b)
            if not clipped:continue
            a,b=clipped;roads.append((a,b,width))
            # Millimetre-scale layering avoids coplanar flicker at joins/crossings.
            layer = len(roads) * .00015
            group="way_"+f["osm_way_id"]
            if not walking:segment(group,a,b,width+2.1,.075+layer,.15,"#d8d5c9",name="Sidewalk")
            segment(group,a,b,width,.17+layer,.12,"#e0d4b8" if walking else "#5c696a","path" if walking else "stone")
            if kind in ("primary","secondary","tertiary","residential"):
                length=math.dist(a,b)
                for t in range(0,int(length)-2,8):
                    start=[a[j]+(b[j]-a[j])*t/length for j in (0,1)]
                    end=[a[j]+(b[j]-a[j])*(t+3)/length for j in (0,1)]
                    segment(group,start,end,.10,.24+layer,.025,"#eee5bd",name="Lane mark")
    estimated=0
    for f in buildings:
        poly=f["points"][:-1];t=f["tags"];group="building_"+f["osm_way_id"]
        try:levels=max(1,min(26,int(float(t.get("building:levels","3")))))
        except ValueError:levels=3
        estimated+=int("building:levels" not in t)
        height=levels*3.0
        fill(group,poly,height,height,"#dbd9cb","concrete")
        fill(group,poly,height+.35,.35,"#7c8984","stone")
        area=sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(poly,poly[1:]+poly[:1]))
        for a,b in zip(poly,poly[1:]+poly[:1]):
            length=math.dist(a,b)
            if length<1:continue
            yaw=-math.degrees(math.atan2(b[1]-a[1],b[0]-a[0]))
            nx,nz=(b[1]-a[1])/length,-(b[0]-a[0])/length
            if area<0:nx,nz=-nx,-nz
            segment(group,a,b,.25,height/2,height,"#e4e0d1",name="Facade wall")
            segment(group,a,b,.5,height+.55,.4,"#e4e0d1",name="Roof edge")
            cols=max(1,int(length/5.8))
            for floor in range(levels):
                for col in range(cols):
                    u=(col+.5)/cols
                    pos=[a[0]+(b[0]-a[0])*u+nx*.17,1.8+floor*3,a[1]+(b[1]-a[1])*u+nz*.17]
                    part(group,"Procedural window",pos,[min(2.4,length/cols*.65),1.65,.10],"#4e727d","glass",yaw,collide=False)
    rng=random.Random(20260920);tree_count=0
    def clearance(x,z,a,b):
        dx,dz=b[0]-a[0],b[1]-a[1];den=dx*dx+dz*dz
        u=max(0,min(1,((x-a[0])*dx+(z-a[1])*dz)/den)) if den else 0
        return math.hypot(x-a[0]-u*dx,z-a[1]-u*dz)
    for _ in range(4500):
        if tree_count>=145:break
        x,z=rng.uniform(-WIDTH/2+5,WIDTH/2-5),rng.uniform(-DEPTH/2+5,DEPTH/2-5)
        if any(inside(x,z,f["points"]) for f in buildings):continue
        if any(clearance(x,z,a,b)<w/2+3 for a,b,w in roads):continue
        height=rng.uniform(4,8);radius=rng.uniform(2,3.4)
        part("planting","Trunk",[x,height*.38,z],[.45,height*.76,.45],"#765f45","wood")
        part("planting","Canopy",[x,height*.8,z],[radius*2,radius*1.4,radius*2],rng.choice(["#668b55","#527648","#74915f"]),"foliage",shape="ball",collide=False)
        tree_count+=1
    # Spawn is selected from an OSM footpath, and no decorative trees occupy roads.
    foot=next((f for f in data["features"] if f["kind"]=="road" and f["tags"].get("highway") in ("footway","path") and all(abs(v)<80 for v in f["points"][0])),None)
    spawn=[foot["points"][0][0],1,foot["points"][0][1]] if foot else [0,1,0]
    part("spawn","Player spawn",spawn,[2,.2,2],"#e6bd78",cls="SpawnLocation")
    digest=hashlib.sha256(json.dumps(data,sort_keys=True).encode()).hexdigest()
    scene={"version":"1.0","component_version":"open-neighbourhood-1.0","name":"Springer Park — open-data study","seed":20260920,"spec_digest":digest,"bounds":{"width":WIDTH*SCALE,"depth":DEPTH*SCALE,"max_height":85*SCALE},"parts":parts,"spawn":{"position":[v*SCALE for v in spawn],"rotation_y":0},"camera":{"position":[270*SCALE,270*SCALE,330*SCALE],"target":[0,12*SCALE,0],"fov":48},"stats":{"part_count":len(parts),"triangle_estimate":len(parts)*24,"compile_ms":0},"attribution":NOTICE,"license":LICENSE}
    meta={"building_count":len(buildings),"tree_count":tree_count,"part_count":len(parts),"area_m":[WIDTH,DEPTH],"estimated_building_heights":estimated,"studs_per_metre":SCALE,"source":"OpenStreetMap vector features","facades":"Original procedural approximation, not photographs","studio_play_tested":False}
    return scene,meta


def main():
    args=argparse.ArgumentParser();args.add_argument("--osm",type=Path);options=args.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    if options.osm:
        data=read_osm(options.osm)
        (OUT/"source.json").write_text(json.dumps(data,ensure_ascii=False,separators=(",",":"))+"\n")
    else:data=json.loads((OUT/"source.json").read_text())
    scene,meta=build(data)
    for name,value in (("scene.json",scene),("metrics.json",meta)):
        (OUT/name).write_text(json.dumps(value,ensure_ascii=False,separators=(",",":"))+"\n")
    # Original SVG plan rendered from the licensed vector data, not map tiles.
    elements=[f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {WIDTH} {DEPTH}" role="img" aria-label="OpenStreetMap building footprints and roads"><rect width="100%" height="100%" fill="#edf0e5"/>']
    for f in data["features"]:
        points=" ".join(f"{x+WIDTH/2:.2f},{z+DEPTH/2:.2f}" for x,z in f["points"])
        if f["kind"]=="building":elements.append(f'<polygon points="{points}" fill="#44685d" stroke="#edf0e5" stroke-width=".6"/>')
        elif f["kind"]=="road":elements.append(f'<polyline points="{points}" fill="none" stroke="#b1b9aa" stroke-width="{1.5 if f["tags"]["highway"] in ("path","footway","steps") else 5}"/>')
    elements.append('<rect x="4" y="275" width="232" height="12" rx="2" fill="#fff"/><text x="8" y="283" font-size="6" font-family="sans-serif" fill="#203b32">© OpenStreetMap contributors · openstreetmap.org/copyright · ODbL</text></svg>')
    (OUT/"plan.svg").write_text("\n".join(elements))
    print(json.dumps(meta,indent=2))


if __name__=="__main__":main()
