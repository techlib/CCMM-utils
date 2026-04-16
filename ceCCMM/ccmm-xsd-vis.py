import xml.etree.ElementTree as ET

def generate_plantuml_simple(xsd_file):
    ns = {'xs': 'http://www.w3.org/2001/XMLSchema'}

    try:
        tree = ET.parse(xsd_file)
        root = tree.getroot()
    except Exception as e:
        print(f"Chyba při čtení souboru: {e}")
        return

    print("@startuml")
    print("skinparam classBackgroundColor #F9F9F9")
    print("hide circle")

    complex_types = root.findall(".//xs:complexType", ns)
    complex_types.sort(key=lambda x: x.get('name', '').lower())

    for c_type in complex_types:
        type_name = c_type.get('name')
        if not type_name:
            continue

        print(f'class "{type_name}" {{')

        items_to_print = []
        unique_keys = set()

        # Projít strukturu typu
        for container in c_type.iter():
            # Specifické zpracování CHOICE
            if container.tag.endswith('choice'):
                choice_elements = []
                min_occ = container.get('minOccurs', '1')
                max_occ = container.get('maxOccurs', '1')
                is_choice_mandatory = min_occ != '0'

                for elem in container.findall("xs:element", ns):
                    name = elem.get('name') or elem.get('ref', '').split(':')[-1]
                    if name not in unique_keys:
                        choice_elements.append(f"**{name}**")
                        unique_keys.add(name)

                if choice_elements:
                    prefix = "*" if is_choice_mandatory else ""
                    choice_line = " | ".join(choice_elements)
                    # Přidání kardinality celého choice bloku
                    cardinality = f"[{min_occ}..{max_occ}]"
                    sort_key = choice_elements[0].replace("*", "").lower()
                    items_to_print.append((sort_key, f"  {prefix} {choice_line} {cardinality}"))

            # Zpracování standardních elementů
            elif container.tag.endswith(('sequence', 'complexType', 'complexContent', 'extension')):
                for elem in container.findall("xs:element", ns):
                    name = elem.get('name') or elem.get('ref', '').split(':')[-1]
                    if name in unique_keys:
                        continue

                    unique_keys.add(name)
                    min_occ = elem.get('minOccurs', '1')
                    max_occ = elem.get('maxOccurs', '1')
                    is_mandatory = min_occ != '0'

                    prefix = "*" if is_mandatory else ""
                    bold = "**" if is_mandatory else ""

                    line = f'  {prefix} {bold}{name}{bold} [{min_occ}..{max_occ}]'
                    items_to_print.append((name.lower(), line))

        # Zpracování atributů
        for attr in c_type.findall(".//xs:attribute", ns):
            attr_name = attr.get('name') or attr.get('ref', '').split(':')[-1]
            if attr_name in unique_keys:
                continue
            unique_keys.add(attr_name)

            is_mandatory = attr.get('use') == 'required'
            prefix = "*" if is_mandatory else ""
            line = f'  {prefix} **{attr_name}** (attr)'
            items_to_print.append((attr_name.lower(), line))

        # Finální výpis seřazený abecedně
        items_to_print.sort(key=lambda x: x[0])
        for _, line in items_to_print:
            print(line)

        print("}")

    print("@enduml")

generate_plantuml_simple('flattenCCMM/ccmm_merged.xsd')
