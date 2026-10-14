import sys
from rdflib import Graph, BNode
from rdflib.compare import to_isomorphic, graph_diff
def load(f):
    g=Graph(); g.parse(f, format='xml'); return g
a,b=load(sys.argv[1]),load(sys.argv[2])
both,oa,ob=graph_diff(to_isomorphic(a),to_isomorphic(b))
def short(x):
    s=str(x)
    for p,n in [('http://www.w3.org/1999/02/22-rdf-syntax-ns#','rdf:'),('http://purl.org/dc/terms/','dct:'),('http://www.w3.org/ns/dcat#','dcat:'),('https://model.ccmm.cz/vocabulary/ccmm#','ccmm:'),('http://www.w3.org/2004/02/skos/core#','skos:'),('http://www.w3.org/ns/prov#','prov:'),('http://www.w3.org/2000/01/rdf-schema#','rdfs:')]:
        s=s.replace(p,n)
    return 'BN' if isinstance(x,BNode) else s[:90]
print(f"triples {len(a)} vs {len(b)}; only-left {len(oa)}; only-right {len(ob)}")
import collections
for name,g in (('-',oa),('+',ob)):
    c=collections.Counter(short(p) for s,p,o in g)
    print(name, dict(c.most_common(30)))
