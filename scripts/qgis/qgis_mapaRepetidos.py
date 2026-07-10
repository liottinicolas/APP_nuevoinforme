import os
import glob
import zipfile
import re
import uuid
import datetime
import xml.etree.ElementTree as ET
import pandas as pd

def find_qgz_files():
    # Buscar el archivo EDLR_PORGID.qgz en la carpeta de REPETIDOS
    base_pattern = r"G:\Desarrollo Ambiental\Limpieza\Spaa\Infograf*\08. MAPAS DIARIOS\02 REPETIDOS\EDLR_PORGID.qgz"
    
    # Resolver ruta real usando glob
    resolved_paths = glob.glob(base_pattern)
    if not resolved_paths:
        raise FileNotFoundError("No se encontró el archivo EDLR_PORGID.qgz en la unidad G:")
    
    return [(resolved_paths[0], "Mapa EDLR_PORGID")]

def get_qgz_path():
    files = find_qgz_files()
    if files:
        return files[0][0]
    raise FileNotFoundError("No se encontró el archivo QGZ.")

def get_latest_local_repite_csv():
    # Buscar todos los archivos CSV locales en la ruta de Trabajo IM
    pattern = r"C:\Users\im4445285\OneDrive\Trabajo IM\APP_nuevoinforme\vistas\informediario\reportes\Mapas\Repite *.csv"
    files = glob.glob(pattern)
    if not files:
        raise FileNotFoundError("No se encontró ningún archivo CSV de tipo Repite en la carpeta local de reportes.")
        
    date_file_pairs = []
    for filepath in files:
        filename = os.path.basename(filepath)
        match = re.search(r"Repite\s+(\d{4}-\d{2}-\d{2})\.csv", filename, re.IGNORECASE)
        if match:
            date_str = match.group(1)
            date_file_pairs.append((date_str, filepath))
            
    if not date_file_pairs:
        raise FileNotFoundError("No se encontraron CSVs locales con el formato Repite AAAA-MM-DD.csv")
        
    # Ordenar por fecha cronológica descendente (el más reciente primero)
    date_file_pairs.sort(key=lambda x: x[0], reverse=True)
    latest_path = date_file_pairs[0][1]
    latest_date = date_file_pairs[0][0]
    
    return latest_path, latest_date

def list_project_layers(qgz_path):
    with zipfile.ZipFile(qgz_path, 'r') as z:
        qgs_filename = [f for f in z.namelist() if f.endswith('.qgs')][0]
        with z.open(qgs_filename) as f:
            tree = ET.parse(f)
            root = tree.getroot()
            
            layers = root.findall(".//maplayer")
            layer_names = []
            for layer in layers:
                name_elem = layer.find("layername")
                if name_elem is not None:
                    layer_names.append(name_elem.text)
            return layer_names

def read_excel_values(csv_date):
    # Buscar el archivo de informe excel con la fecha correspondiente
    pattern = f"C:\\Users\\im4445285\\OneDrive\\Trabajo IM\\APP_nuevoinforme\\vistas\\informediario\\reportes\\archivo_informe {csv_date} *.xlsx"
    files = glob.glob(pattern)
    if not files:
        print(f"[-] No se encontró el archivo excel de informe para la fecha {csv_date}")
        return None
        
    excel_path = files[0]
    print(f"[+] Leyendo valores desde excel: {os.path.basename(excel_path)}")
    try:
        # data_only=True en openpyxl (usado por pandas internamente) lee el valor cacheado de las fórmulas
        df = pd.read_excel(excel_path, sheet_name="Datos Mapas", header=None)
        
        # Q es la columna 16 (A=0, ..., Q=16)
        # Q2 -> Fila 2 (indice 1) -> Cantidad Repetidos
        # Q3 -> Fila 3 (indice 2) -> Cantidad Levantados
        # Q4 -> Fila 4 (indice 3) -> % Repetidos
        
        values = {}
        
        # Cantidad Repetidos (Q2)
        q2_val = df.iloc[1, 16]
        if pd.isna(q2_val):
            values["Cantidad Repetidos"] = "0"
        elif isinstance(q2_val, (int, float)):
            values["Cantidad Repetidos"] = str(int(round(q2_val)))
        else:
            values["Cantidad Repetidos"] = str(q2_val).strip()
            
        # Cantidad Levantados (Q3)
        q3_val = df.iloc[2, 16]
        if pd.isna(q3_val):
            values["Cantidad Levantados"] = "0"
        elif isinstance(q3_val, (int, float)):
            values["Cantidad Levantados"] = str(int(round(q3_val)))
        else:
            values["Cantidad Levantados"] = str(q3_val).strip()
            
        # % Repetidos (Q4)
        q4_val = df.iloc[3, 16]
        if pd.isna(q4_val):
            values["% Repetidos"] = "0,00%"
        elif isinstance(q4_val, (int, float)):
            if q4_val <= 1.0:
                values["% Repetidos"] = f"{q4_val * 100:.2f}%".replace(".", ",")
            else:
                values["% Repetidos"] = f"{q4_val:.2f}%".replace(".", ",")
        else:
            values["% Repetidos"] = str(q4_val).strip()
            
        for k, v in values.items():
            print(f"    {k}: {v}")
            
        return values
    except Exception as e:
        print(f"[-] Error al leer el archivo excel: {e}")
        return None

def update_qgis_print_layout(root, csv_date):
    print("\n[+] Analizando composición de impresión para actualización de textos...")
    
    try:
        dt = datetime.datetime.strptime(csv_date, "%Y-%m-%d")
    except ValueError as ve:
        print(f"[-] Error al parsear la fecha {csv_date}: {ve}")
        return False
        
    dias_semana = {
        0: "Lunes",
        1: "Martes",
        2: "Miércoles",
        3: "Jueves",
        4: "Viernes",
        5: "Sábado",
        6: "Domingo"
    }
    weekday_name = dias_semana[dt.weekday()]
    formatted_date = dt.strftime("%d/%m/%Y")
    filename_pdf = f"EDCR {csv_date}.pdf"
    
    # Intentamos buscar posibles nombres de composición
    layout_names = ["MAPA GRAL MVD", "REPETIDOS", "ESTADO DE LEVANTE"]
    layout = None
    for name in layout_names:
        for l in root.findall(".//Layout"):
            if l.attrib.get("name") == name:
                layout = l
                print(f"[+] Composición encontrada: '{name}'")
                break
        if layout is not None:
            break
            
    if layout is None:
        print("[-] Advertencia: No se encontró ninguna composición de impresión conocida.")
        return False
        
    # Leer valores desde el Excel
    excel_values = read_excel_values(csv_date)
    
    modified = False
    
    # Modificar elementos dentro del Layout (el título queda igual, no se modifica)
    for item in layout.iter():
        if item.tag == "LayoutItem":
            item_id = item.attrib.get("id", "")
            label_text = item.attrib.get("labelText", "")
            
            # A. Elemento 'Dia'
            if item_id == "Dia":
                if label_text != weekday_name:
                    item.attrib["labelText"] = weekday_name
                    print(f"    [~] 'Dia' actualizado: '{weekday_name}'")
                    modified = True
                    
            # B. Elemento 'Fecha'
            elif item_id == "Fecha":
                if label_text != formatted_date:
                    item.attrib["labelText"] = formatted_date
                    print(f"    [~] 'Fecha' actualizado: '{formatted_date}'")
                    modified = True
                    
            # C. Elemento 'Nombre archivo' o 'Texto archivo'
            elif item_id in ["Nombre archivo", "Texto archivo"]:
                if label_text != filename_pdf:
                    item.attrib["labelText"] = filename_pdf
                    print(f"    [~] '{item_id}' actualizado: '{filename_pdf}'")
                    modified = True
                    
            # D. Elementos traídos del excel para repetidos
            elif item_id in ["Cantidad Levantados", "Cantidad Repetidos", "% Repetidos"]:
                if excel_values and item_id in excel_values:
                    new_val = excel_values[item_id]
                    if label_text != new_val:
                        item.attrib["labelText"] = new_val
                        print(f"    [~] '{item_id}' actualizado: '{new_val}'")
                        modified = True
                    
    return modified

def add_csv_layer_to_qgis_project(qgz_path, csv_path, layer_name, csv_date, group_name="DATOS"):
    print(f"\n[+] Procesando capa '{layer_name}' en el proyecto QGIS...")
    temp_qgz_path = qgz_path + ".tmp"
    modified = False
    layer_id = None
    
    # 1. Leer el ZIP original (.qgz)
    with zipfile.ZipFile(qgz_path, 'r') as z_in:
        qgs_filename = [f for f in z_in.namelist() if f.endswith('.qgs')][0]
        qgs_content = z_in.read(qgs_filename)
        root = ET.fromstring(qgs_content)
        
        # 2. Verificar si la capa ya existe
        existing_layers = root.findall(".//maplayer")
        existing_layer = None
        for layer in existing_layers:
            name_elem = layer.find("layername")
            if name_elem is not None and name_elem.text == layer_name:
                existing_layer = layer
                break
                
        if existing_layer is not None:
            # Obtener su ID
            layer_id_elem = existing_layer.find("id")
            if layer_id_elem is not None:
                layer_id = layer_id_elem.text
            
            # Verificar si la ruta del CSV coincide
            datasource_elem = existing_layer.find("datasource")
            if datasource_elem is not None and datasource_elem.text == csv_path:
                print(f"[!] La capa '{layer_name}' ya existe y apunta a la ruta local correcta.")
            else:
                print(f"[~] Redireccionando capa existente '{layer_name}'...")
                print(f"    Ruta anterior: {datasource_elem.text if datasource_elem is not None else 'N/A'}")
                print(f"    Ruta nueva:    {csv_path}")
                
                # Actualizar origen en <datasource>
                if datasource_elem is not None:
                    datasource_elem.text = csv_path
                else:
                    datasource_elem = ET.SubElement(existing_layer, "datasource")
                    datasource_elem.text = csv_path
                    
                # Actualizar origen en <provider>
                provider_elem = existing_layer.find("provider")
                if provider_elem is not None:
                    provider_elem.attrib["encoding"] = "UTF-8"
                
                # Actualizar en <layer-tree-group>
                if layer_id:
                    layer_tree_elem = root.find(".//layer-tree-group")
                    if layer_tree_elem is not None:
                        for tree_layer in layer_tree_elem.findall(".//layer-tree-layer"):
                            if tree_layer.attrib.get("id") == layer_id:
                                tree_layer.attrib["source"] = csv_path
                                print(f"[+] Árbol de capas (layer-tree-layer) actualizado para la ID '{layer_id}'.")
                
                modified = True
                
        # 3. Si no existe la capa, crear una nueva con el campo Repite
        else:
            unique_suffix = str(uuid.uuid4()).replace("-", "_")
            layer_id = f"{layer_name.replace(' ', '_')}_{unique_suffix}"
            
            maplayers_elem = root.find(".//projectlayers")
            if maplayers_elem is None:
                print("[-] Error: No se encontró la sección <projectlayers> en el proyecto.")
                return False
                
            new_layer_xml = f"""<maplayer autoRefreshTime="0" legendPlaceholderImage="" styleCategories="AllStyleCategories" geometry="No geometry" maxScale="0" type="vector" autoRefreshEnabled="0" wkbType="NoGeometry" refreshOnNotifyMessage="" hasScaleBasedVisibilityFlag="0" refreshOnNotifyEnabled="0" readOnly="0" minScale="1e+08">
  <id>{layer_id}</id>
  <datasource>{csv_path}</datasource>
  <keywordList><value /></keywordList>
  <layername>{layer_name}</layername>
  <srs>
    <spatialrefsys nativeFormat="Wkt">
      <wkt />
      <proj4 />
      <srsid>0</srsid>
      <srid>0</srid>
      <authid />
      <description />
      <projectionacronym />
      <ellipsoidacronym />
      <geographicflag>false</geographicflag>
    </spatialrefsys>
  </srs>
  <provider encoding="UTF-8">ogr</provider>
  <vectorjoins />
  <layerDependencies />
  <dataDependencies />
  <expressionfields />
  <map-layer-style-manager current="predeterminado">
    <map-layer-style name="predeterminado" />
  </map-layer-style-manager>
  <auxiliaryLayer />
  <metadataUrls />
  <flags>
    <Identifiable>1</Identifiable>
    <Removable>1</Removable>
    <Searchable>1</Searchable>
    <Private>0</Private>
  </flags>
  <temporal endField="" endExpression="" durationUnit="min" limitMode="0" mode="0" startExpression="" startField="" durationField="" accumulate="0" fixedDuration="0" enabled="0">
    <fixedRange><start></start><end></end></fixedRange>
  </temporal>
  <customproperties><Option /></customproperties>
  <geometryOptions removeDuplicateNodes="0" geometryPrecision="0">
    <activeChecks />
    <checkConfiguration />
  </geometryOptions>
  <referencedLayers />
  <fieldConfiguration>
    <field name="GID" configurationFlags="NoFlag">
      <editWidget type="TextEdit"><options><Option /></options></editWidget>
    </field>
    <field name="Repite" configurationFlags="NoFlag">
      <editWidget type="TextEdit"><options><Option /></options></editWidget>
    </field>
  </fieldConfiguration>
  <aliases>
    <alias field="GID" index="0" name="" />
    <alias field="Repite" index="1" name="" />
  </aliases>
  <splitPolicies>
    <policy field="GID" policy="Duplicate" />
    <policy field="Repite" policy="Duplicate" />
  </splitPolicies>
  <defaults>
    <default field="GID" expression="" applyOnUpdate="0" />
    <default field="Repite" expression="" applyOnUpdate="0" />
  </defaults>
  <constraints>
    <constraint field="GID" exp_strength="0" constraints="0" unique_strength="0" notnull_strength="0" />
    <constraint field="Repite" exp_strength="0" constraints="0" unique_strength="0" notnull_strength="0" />
  </constraints>
  <constraintExpressions>
    <constraint field="GID" exp="" desc="" />
    <constraint field="Repite" exp="" desc="" />
  </constraintExpressions>
  <attributeactions>
    <defaultAction key="Canvas" value="{{{{00000000-0000-0000-0000-000000000000}}}}" />
  </attributeactions>
  <attributetableconfig sortOrder="0" actionWidgetStyle="DropDown" sortExpression="">
    <columns>
      <column type="field" hidden="0" width="-1" name="GID" />
      <column type="field" hidden="0" width="-1" name="Repite" />
      <column type="actions" hidden="1" width="-1" />
    </columns>
  </attributetableconfig>
  <conditionalstyles>
    <rowstyles />
    <fieldstyles />
  </conditionalstyles>
  <storedreports />
  <editform tolerant="1"></editform>
  <editforminit />
  <editforminitcodesource>0</editforminitcodesource>
  <editforminitfilepath></editforminitfilepath>
  <editforminitcode><![CDATA[]]></editforminitcode>
  <featformsuppress>0</featformsuppress>
  <editorlayout>GeneratedLayout</editorlayout>
  <editable>
    <field name="GID" editable="1" />
    <field name="Repite" editable="1" />
  </editable>
  <labelOnTop>
    <field labelOnTop="0" name="GID" />
    <field labelOnTop="0" name="Repite" />
  </labelOnTop>
  <reuseLastValue>
    <field name="GID" reuseLastValue="0" />
    <field name="Repite" reuseLastValue="0" />
  </reuseLastValue>
  <dataDefinedFieldProperties/>
</maplayer>"""
            new_layer_node = ET.fromstring(new_layer_xml)
            maplayers_elem.append(new_layer_node)
            
            # Encontrar o crear subgrupo "DATOS"
            layer_tree_elem = root.find(".//layer-tree-group")
            if layer_tree_elem is None:
                print("[-] Error: No se encontró la etiqueta <layer-tree-group>.")
                return False
                
            target_group = None
            for group in layer_tree_elem.findall(".//layer-tree-group"):
                if group.attrib.get("name") == group_name:
                    target_group = group
                    break
                    
            if target_group is None:
                print(f"[+] Grupo '{group_name}' no encontrado en el árbol de capas. Creándolo...")
                target_group = ET.Element("layer-tree-group", expanded="1", checked="Qt::Checked", groupLayer="", name=group_name)
                target_group.append(ET.Element("customproperties"))
                layer_tree_elem.insert(0, target_group)
                
            new_tree_layer_xml = f"""<layer-tree-layer providerKey="ogr" checked="Qt::Checked" expanded="1" legend_split_behavior="0" id="{layer_id}" legend_exp="" patch_size="-1,-1" name="{layer_name}" source="{csv_path}">
  <customproperties><Option /></customproperties>
</layer-tree-layer>"""
            new_tree_layer_node = ET.fromstring(new_tree_layer_xml)
            target_group.insert(1, new_tree_layer_node)
            modified = True
            
        # 3.5. Crear/Actualizar la unión (Vector Join) y Simbología en la capa "ide:ide_V_DF_POSICIONES_RECORRIDO_GEOM"
        if layer_id:
            target_join_layer_name = "ide:ide_V_DF_POSICIONES_RECORRIDO_GEOM"
            target_join_layer = None
            for layer in existing_layers:
                name_elem = layer.find("layername")
                if name_elem is not None and name_elem.text == target_join_layer_name:
                    target_join_layer = layer
                    break
                    
            if target_join_layer is not None:
                # --- PARTE A: UNIÓN (JOIN) ---
                vectorjoins_elem = target_join_layer.find("vectorjoins")
                if vectorjoins_elem is None:
                    vectorjoins_elem = ET.SubElement(target_join_layer, "vectorjoins")
                    
                already_joined = False
                for join in vectorjoins_elem.findall("join"):
                    if join.attrib.get("joinLayerId") == layer_id:
                        already_joined = True
                        break
                        
                if not already_joined:
                    print(f"[+] Creando unión (Join) de la capa '{layer_name}' con '{target_join_layer_name}' por el atributo 'GID'...")
                    join_attribs = {
                        "dynamicForm": "0",
                        "memoryCache": "1",
                        "editable": "0",
                        "upsertOnEdit": "0",
                        "joinLayerId": layer_id,
                        "joinFieldName": "GID",
                        "cascadedDelete": "0",
                        "targetFieldName": "GID"
                    }
                    new_join_elem = ET.Element("join", attrib=join_attribs)
                    vectorjoins_elem.append(new_join_elem)
                    modified = True
                else:
                    print(f"[!] La unión de '{layer_name}' con '{target_join_layer_name}' por 'GID' ya está creada.")
                
                # --- PARTE B: SIMBOLOGÍA (SYMBOLOGY) ---
                renderer_elem = target_join_layer.find("renderer-v2")
                if renderer_elem is not None and renderer_elem.attrib.get("type") == "categorizedSymbol":
                    old_styling_field = renderer_elem.attrib.get("attr")
                    new_styling_field = f"{layer_name}_Repite"
                    
                    if old_styling_field != new_styling_field:
                        print(f"[+] Actualizando simbología categorizada en '{target_join_layer_name}':")
                        print(f"    Atributo anterior: '{old_styling_field}'")
                        print(f"    Atributo nuevo:    '{new_styling_field}'")
                        
                        layer_xml_str = ET.tostring(target_join_layer, encoding='utf-8').decode('utf-8')
                        updated_layer_xml_str = layer_xml_str.replace(old_styling_field, new_styling_field)
                        updated_layer_node = ET.fromstring(updated_layer_xml_str)
                        
                        projectlayers_elem = root.find(".//projectlayers")
                        if projectlayers_elem is not None:
                            for idx, child in enumerate(projectlayers_elem):
                                child_name = child.find("layername")
                                if child_name is not None and child_name.text == target_join_layer_name:
                                    projectlayers_elem[idx] = updated_layer_node
                                    target_join_layer = updated_layer_node
                                    break
                        modified = True
                    else:
                        print(f"[!] La simbología de '{target_join_layer_name}' ya está categorizada por '{new_styling_field}'.")
            else:
                print(f"[-] Advertencia: No se encontró la capa de destino '{target_join_layer_name}' para realizar la unión/simbología.")
                
        # 3.7. Actualizar los textos de la composición de impresión (Layout)
        if update_qgis_print_layout(root, csv_date):
            modified = True
        
        # 4. Guardar los cambios si hubo modificación
        if modified:
            with zipfile.ZipFile(temp_qgz_path, 'w', zipfile.ZIP_DEFLATED) as z_out:
                for item in z_in.infolist():
                    if item.filename != qgs_filename:
                        z_out.writestr(item, z_in.read(item.filename))
                new_xml_data = ET.tostring(root, encoding='utf-8')
                z_out.writestr(qgs_filename, new_xml_data)
                
    # Reemplazar el archivo original fuera del bloque "with z_in" para liberar el handle del archivo
    if modified:
        os.replace(temp_qgz_path, qgz_path)
        print(f"[+] Proyecto QGIS actualizado con éxito.")
        return True
            
    return False

if __name__ == "__main__":
    try:
        # 1. Obtener la ruta del archivo QGIS activo
        qgz_path = get_qgz_path()
        print("\n" + "=" * 80)
        print(f" PROYECTO QGIS ACTIVO: {qgz_path}")
        print("=" * 80)
        
        # 2. Buscar el último CSV local en la ruta solicitada
        print("\n[+] Buscando el último archivo CSV en la carpeta local de reportes...")
        csv_path, csv_date = get_latest_local_repite_csv()
        layer_name = f"Repite {csv_date}"
        formatted_csv_path = csv_path.replace("\\", "/")
        print(f"    Archivo encontrado: {os.path.basename(csv_path)}")
        print(f"    Ruta del archivo: {formatted_csv_path}")
        
        # 3. Leer capas actuales
        layers_before = list_project_layers(qgz_path)
        print(f"\n    Capas actuales en el proyecto ({len(layers_before)}):")
        
        # 4. Modificar el proyecto QGIS (Capa, Unión, Simbología y Textos de Composición)
        success = add_csv_layer_to_qgis_project(qgz_path, formatted_csv_path, layer_name, csv_date, group_name="DATOS")
        
        # 5. Si se modificó con éxito, mostrar la lista de capas actualizada
        if success:
            layers_after = list_project_layers(qgz_path)
            print(f"\n[+] Capas actualizadas en el proyecto ({len(layers_after)}):")
            for i, name in enumerate(layers_after, 1):
                if name == layer_name:
                    print(f"  [{i:02d}] {name}  <-- ¡CAPA RECIÉN AGREGADA AL GRUPO 'DATOS'!")
                else:
                    print(f"  [{i:02d}] {name}")
        else:
            print("\n[-] No se realizaron modificaciones en el proyecto QGIS.")
            
    except PermissionError as pe:
        print(f"\n[!] ERROR DE PERMISOS DETALLADO: {pe}")
        import traceback; traceback.print_exc()
        print("    Por favor, asegúrate de CERRAR QGIS Desktop antes de ejecutar el script para que pueda modificarse.")
    except Exception as e:
        print(f"\n[-] Error general durante la ejecución: {e}")
