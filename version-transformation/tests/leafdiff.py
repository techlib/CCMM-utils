import sys, collections
from lxml import etree
def leaves(f):
    t=etree.parse(f, etree.XMLParser(remove_blank_text=True, remove_comments=True))
    c=collections.Counter()
    def walk(e, path):
        ln=etree.QName(e).localname
        p=path+'/'+ln
        for k,v in e.attrib.items():
            k2=etree.QName(k).localname
            if k2=='schemaLocation': continue
            if k2=='lang': continue
            c[(p+'/@'+k2, ' '.join(v.split()))]+=1
        kids=[k for k in e if isinstance(k.tag,str)]
        if not kids:
            lang=e.get('{http://www.w3.org/XML/1998/namespace}lang')
            c[(p+(f'[{lang}]' if lang is not None else ''), ' '.join((e.text or '').split()))]+=1
        for k in kids: walk(k,p)
    walk(t.getroot(),'')
    return c
a,b=leaves(sys.argv[1]),leaves(sys.argv[2])
only_a=a-b; only_b=b-a
for (p,v),n in sorted(only_a.items()): print('-',p,'=',v[:110])
for (p,v),n in sorted(only_b.items()): print('+',p,'=',v[:110])
