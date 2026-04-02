import os
import datetime
import xlwings as xw
import pandas as pd
import pyreadr
import shutil

def update_excel_with_xlwings(filepath, output_filename):
    output_path = os.path.join(os.path.dirname(filepath), output_filename)
    
    print(f"Resguardando archivo original. Creando copia de trabajo: {output_path}")
    # Copiamos primero para garantizar que el archivo original no sea tocado por Excel
    shutil.copy2(filepath, output_path)
    
    print("Iniciando Excel en segundo plano para procesar la copia...")
    
# add_book=False evita que Excel cree un "Libro1" vacío al abrirse
    app = xw.App(visible=False, add_book=False)
    app.display_alerts = False       # Desactiva avisos (ej: "Desea guardar cambios")
    app.screen_updating = False      # Evita parpadeos y acelera el proceso
    # --------------------------

    try:
        # Si estás en OneDrive, un pequeño delay ayuda a evitar el bloqueo por sincronización
        import time
        time.sleep(1) 
        
        # Abrir el workbook (la copia que ya hicimos)
        wb = app.books.open(output_path)
        
        hojas = [sheet.name for sheet in wb.sheets]
        
        if 'Hoy' not in hojas:
            raise ValueError("El archivo no contiene la hoja 'Hoy'.")
            
        nombre_ayer = "Ayer" if "Ayer" in hojas else ("ayer" if "ayer" in hojas else None)
        if not nombre_ayer:
             raise ValueError("El archivo no contiene ninguna hoja llamada 'Ayer' o 'ayer'.")
             
        hoja_hoy = wb.sheets['Hoy']
        hoja_ayer = wb.sheets[nombre_ayer]
        
        print("Obteniendo todos los valores de 'Hoy'...")
        # .options(empty='').value obtiene todos los datos usados sin arrastrar formulas
        # current_region obtiene el bloque contiguo de datos desde A1. Otra opción es 'used_range' 
        datos_hoy = hoja_hoy.used_range.value
        
        # En caso de que sea solo una celda se convierte a lista de listas para procesar standard
        if not isinstance(datos_hoy, list):
            datos_hoy = [[datos_hoy]]
        elif len(datos_hoy) > 0 and not isinstance(datos_hoy[0], list):
             datos_hoy = [datos_hoy] # 1D list a 2D list
             
        # Limpiar filas en blanco al final de la lectura
        while datos_hoy and all(v is None or str(v).strip() == '' for v in datos_hoy[-1]):
            datos_hoy.pop()

        filas_copiadas = len(datos_hoy)
        print(f"Copiando {filas_copiadas} filas (como valor) a '{nombre_ayer}'...")
        
        # Escribir los valores como un bloque masivo en A1, sobreescribiendo fórmulas existentes 
        # en ese rango proveniende de 'hoy'. Mucho más rapido que iterar como openpyxl.
        if filas_copiadas > 0:
            hoja_ayer.range('A1').value = datos_hoy
        
        # Identificar qué filas existían en Ayer y borrarlas si sobran
        rango_usado_ayer = hoja_ayer.used_range
        max_row_ayer = rango_usado_ayer.last_cell.row
        
        if max_row_ayer > filas_copiadas:
            filas_a_borrar = max_row_ayer - filas_copiadas
            print(f"Borrando {filas_a_borrar} filas sobrantes por debajo de la fila {filas_copiadas} en '{nombre_ayer}'...")
            
            # Formatear el string para borrar toda la fila, eg '100:150'
            hoja_ayer.range(f'{filas_copiadas + 1}:{max_row_ayer}').api.Delete()

        # === NUEVO REQUERIMIENTO: LIMPIAR COLUMNAS EN HOY, Levantado, NoLevantado ===
        
        # 1. Limpiar columnas en 'Hoy' (A, B, I, J, K, L, M) desde la fila 2
        print("Limpiando columnas especificas en 'Hoy'...")
        max_row_hoy = hoja_hoy.used_range.last_cell.row
        if max_row_hoy > 1:
            # Seleccionamos las columnas a limpiar
            columnas_hoy = ['A', 'B', 'I', 'J', 'K', 'L', 'M']
            for col in columnas_hoy:
                rango_str = f"{col}2:{col}{max_row_hoy}"
                hoja_hoy.range(rango_str).clear_contents()
                
        # === OBTENER FECHA EN COLUMNA C ANTES DE BORRAR ===
        import datetime
        fecha_viaje_dt = None
        hojas_secundarias = ['Levantado', 'NoLevantado']
        
        for nombre_hoja in hojas_secundarias:
            if nombre_hoja in hojas and fecha_viaje_dt is None:
                hoja_sec = wb.sheets[nombre_hoja]
                max_row_sec = hoja_sec.used_range.last_cell.row
                if max_row_sec > 1:
                    val_c2 = hoja_sec.range('C2').value
                    if val_c2 is not None:
                        try:
                            if isinstance(val_c2, (int, float)):
                                # Excel tiene un bug heredado de Lotus 1-2-3 donde asume que 1900 fue bisiesto
                                # Por lo tanto, para toda fecha despues del 1 de marzo 1900, al valor serial de Excel (ej. 46083) 
                                # se le debe restar 2 días y sumar a la fecha base 01/01/1900.
                                # Así, 46083 -> 2026-03-02 y 46082 -> 2026-03-01
                                if val_c2 > 59:
                                    dias_reales = val_c2 - 2
                                else:
                                    dias_reales = val_c2 - 1
                                    
                                fecha_viaje_dt = datetime.datetime(1900, 1, 1) + datetime.timedelta(days=dias_reales)
                                
                            elif isinstance(val_c2, datetime.datetime):
                                fecha_viaje_dt = val_c2
                            elif isinstance(val_c2, str):
                                # Intenta parsear texto, ej. "3/2/2026" o "03/02/2026"
                                val_c2 = val_c2.strip()
                                for fmt in ("%d/%m/%Y", "%Y-%m-%d", "%d-%m-%Y"):
                                    try:
                                        fecha_viaje_dt = datetime.datetime.strptime(val_c2, fmt)
                                        break
                                    except ValueError:
                                        pass
                                        
                            if fecha_viaje_dt:
                                print(f"Fecha extraída ('dia_viaje') de {nombre_hoja} en C2: {fecha_viaje_dt.strftime('%d/%m/%Y')} (Valor original: {val_c2})")
                        except Exception as e:
                            print(f"Error al transformar la fecha en {nombre_hoja}!C2: {e}")

        # === FILTRAR RDS CON FECHA + 1 DIA ===
        df_ubicaciones_filtrado = None
        df_llenado_filtrado = None
        fecha_objetivo_date_str = "Desconocida"
        exito = False
        
        if fecha_viaje_dt is None:
            print("\nERROR CRÍTICO: No se pudo extraer la fecha 'dia_viaje' de la celda C2 en Levantado o NoLevantado.")
            print("Cancelando la actualización. El archivo original no ha sido modificado.")
            app.display_alerts = False
            return exito
            
        fecha_objetivo = fecha_viaje_dt + datetime.timedelta(days=1)
        fecha_objetivo_date = fecha_objetivo.date()
        fecha_objetivo_date_str = fecha_objetivo_date.strftime('%Y-%m-%d')
        print(f"La fecha objetivo para filtrar RDS es: {fecha_objetivo_date_str}")
        
        try:
            # Construir rutas hacia la carpeta db (asumiendo estructura: APP_nuevoinforme/vistas/informediario/.../archivo)
            base_dir = os.path.dirname(os.path.abspath(filepath))  # 2026-03-03 (o similar)
            app_dir = os.path.dirname(os.path.dirname(os.path.dirname(base_dir))) # APP_nuevoinforme
            db_dir = os.path.join(app_dir, "db")
            
            ruta_ubicaciones = os.path.join(db_dir, "10393_ubicaciones", "historico_ubicaciones.rds")
            ruta_llenado = os.path.join(db_dir, "GOL_reportes", "historico_llenadoGol.rds")
            
            print("Cargando y filtrando historico_ubicaciones.rds...")
            if os.path.exists(ruta_ubicaciones):
                df_ubicaciones = pyreadr.read_r(ruta_ubicaciones)[None]
                df_ubicaciones['Fecha_dt'] = pd.to_datetime(df_ubicaciones['Fecha'], dayfirst=False).dt.date
                df_ubicaciones_filtrado = df_ubicaciones[df_ubicaciones['Fecha_dt'] == fecha_objetivo_date].copy()
                print(f"  -> historico_ubicaciones filtrado: {len(df_ubicaciones_filtrado)} registros encontrados para {fecha_objetivo_date_str}.")
            else:
                print(f"Advertencia: No se encontro el archivo de ubicaciones en {ruta_ubicaciones}")
            
            print("Cargando y filtrando historico_llenadoGol.rds...")
            if os.path.exists(ruta_llenado):
                df_llenado = pyreadr.read_r(ruta_llenado)[None]
                df_llenado['Fecha_dt'] = pd.to_datetime(df_llenado['Fecha'], dayfirst=False).dt.date
                df_llenado_filtrado = df_llenado[df_llenado['Fecha_dt'] == fecha_objetivo_date].copy()
                print(f"  -> historico_llenado filtrado: {len(df_llenado_filtrado)} registros encontrados para {fecha_objetivo_date_str}.")
            else:
                print(f"Advertencia: No se encontro el archivo de llenado en {ruta_llenado}")
                
        except Exception as e:
            print(f"Error al cargar o filtrar archivos RDS: {e}")

        # === COMPROBACIÓN POSTERIOR A RDS ===
        # Si alguno de los dos está vacío o es None, detenemos todo para no generar un archivo basura
        if (df_ubicaciones_filtrado is None or df_ubicaciones_filtrado.empty) or (df_llenado_filtrado is None or df_llenado_filtrado.empty):
            print(f"\nERROR: No se encontraron registros para la fecha {fecha_objetivo_date_str} en uno o ambos archivos RDS.")
            print("El proceso ha sido cancelado para proteger la estructura del excel.")
            
            # Forzamos cierre sin guardar cambios (se maneja en el finally)
            app.display_alerts = False
            return exito

        # === NUEVO: ESCRIBIR DATOS DE UBICACIONES EN HOJA 'Hoy' ===
        if df_ubicaciones_filtrado is not None and not df_ubicaciones_filtrado.empty:
            print(f"Escribiendo datos de ubicaciones en columnas A,B,I,J,K,L,M de 'Hoy'...")
            # Usar objetos pandas DateFrame directo con las opciones de xlwings para evitar errores de conversion o de dimensiones
            df_AB = df_ubicaciones_filtrado[['gid', 'Circuito']].fillna("")
            df_I_M = df_ubicaciones_filtrado[['Posicion', 'Estado', 'Calle', 'Numero', 'Observaciones']].fillna("")
            
            # Opciones de volcado: omitir el index de pandas y el header (nombre de columna).
            hoja_hoy.range('A2').options(index=False, header=False).value = df_AB
            hoja_hoy.range('I2').options(index=False, header=False).value = df_I_M
            
            cant_filas_nuevas = len(df_AB)
            print(f"  -> Se escribieron {cant_filas_nuevas} filas en la hoja 'Hoy'.")

            # === AJUSTE DE FORMULAS (C:H y N:P) EN HOJA 'Hoy' ===
            print("Ajustando formulas en columnas C:H y N:P de 'Hoy'...")
            fila_final_esperada = 1 + cant_filas_nuevas
            
            # 1. Extender fórmulas desde la fila 2 hacia abajo si hay más de 1 fila de datos
            if fila_final_esperada > 2:
                # C:H
                rango_origen_ch = hoja_hoy.range('C2:H2')
                rango_destino_ch = hoja_hoy.range(f'C2:H{fila_final_esperada}')
                rango_origen_ch.api.AutoFill(rango_destino_ch.api, 0)
                
                # N:P
                rango_origen_np = hoja_hoy.range('N2:P2')
                rango_destino_np = hoja_hoy.range(f'N2:P{fila_final_esperada}')
                rango_origen_np.api.AutoFill(rango_destino_np.api, 0)
                
            # 2. Borrar formulas sobrantes
            if max_row_hoy > fila_final_esperada:
                print(f"  -> Borrando formulas sobrantes abajo de la fila {fila_final_esperada} (hasta {max_row_hoy}).")
                hoja_hoy.range(f'C{fila_final_esperada + 1}:H{max_row_hoy}').clear_contents()
                hoja_hoy.range(f'N{fila_final_esperada + 1}:P{max_row_hoy}').clear_contents()

        # === NUEVO: ESCRIBIR DATOS EN 'Levantado' y 'NoLevantado' ===
        if df_llenado_filtrado is not None and not df_llenado_filtrado.empty:
            columnas_destino = [
                'Fecha', 'Circuito_corto', 'Posicion', 'Levantado', 
                'Porcentaje_llenado', 'Incidencia', 'contenedor_activo', 
                'Condicion', 'Id_viaje_GOL', 'Turno_levantado', 
                'Fecha_hora_pasaje', 'Numero_caja', 'gid', 'the_geom', 'Direccion'
            ]
            
            # Asegurarnos de que las columnas existan, si no, crear vacíias
            for col in columnas_destino:
                if col not in df_llenado_filtrado.columns:
                    df_llenado_filtrado[col] = ""
                    
            # Pyreadr extrae DataFrames con tipos "Categorical" (R factors). 
            # Llenarlos con un str ("") causa error en pandas. Convertir columnas destino a string primero.
            df_destino = df_llenado_filtrado[columnas_destino].copy()
            for col in df_destino.select_dtypes(['category']).columns:
                df_destino[col] = df_destino[col].astype(str)
                
            # Formatear explícitamente la columna 'Fecha' a 'dd/mm/yyyy' antes de exportar
            if 'Fecha' in df_destino.columns:
                df_destino['Fecha'] = pd.to_datetime(df_destino['Fecha']).dt.strftime('%d/%m/%Y')
                
                
            # 1. 'Levantado' (S)
            df_lev = df_destino[df_destino['Levantado'] == 'S'].fillna("")
            cant_lev = len(df_lev)
            if 'Levantado' in hojas and cant_lev > 0:
                print(f"Escribiendo {cant_lev} filas en 'Levantado' desde C2...")
                hoja_lev = wb.sheets['Levantado']
                hoja_lev.range('C2').options(index=False, header=False).value = df_lev
                
                # Ajuste de fórmulas en A:B y limpieza hacia abajo para 'Levantado'
                fila_final_lev = 1 + cant_lev
                
                # 1. Extender fórmulas de A2:B2 hacia abajo
                if fila_final_lev > 2:
                    rango_origen_lev = hoja_lev.range('A2:B2')
                    rango_destino_lev = hoja_lev.range(f'A2:B{fila_final_lev}')
                    rango_origen_lev.api.AutoFill(rango_destino_lev.api, 0)
                    
                # 2. Limpiar cualquier fila por debajo de la data copiada
                max_row_lev = hoja_lev.used_range.last_cell.row
                if max_row_lev > fila_final_lev:
                    hoja_lev.range(f'A{fila_final_lev + 1}:Q{max_row_lev}').clear_contents()
                        
            # 2. 'NoLevantado' (N o NA)
            df_nolev = df_destino[df_destino['Levantado'].isin(['N', '']) | df_destino['Levantado'].isna()].fillna("")
            cant_nolev = len(df_nolev)
            if 'NoLevantado' in hojas and cant_nolev > 0:
                print(f"Escribiendo {cant_nolev} filas en 'NoLevantado' desde C2...")
                hoja_nolev = wb.sheets['NoLevantado']
                hoja_nolev.range('C2').options(index=False, header=False).value = df_nolev
                
                # Ajuste de fórmulas en A:B y limpieza hacia abajo para 'NoLevantado'
                fila_final_nolev = 1 + cant_nolev
                
                # 1. Extender fórmulas de A2:B2 hacia abajo
                if fila_final_nolev > 2:
                    rango_origen_nolev = hoja_nolev.range('A2:B2')
                    rango_destino_nolev = hoja_nolev.range(f'A2:B{fila_final_nolev}')
                    rango_origen_nolev.api.AutoFill(rango_destino_nolev.api, 0)
                    
                # 2. Limpiar cualquier fila por debajo de la data copiada
                max_row_nolev = hoja_nolev.used_range.last_cell.row
                if max_row_nolev > fila_final_nolev:
                    hoja_nolev.range(f'A{fila_final_nolev + 1}:Q{max_row_nolev}').clear_contents()

        # === NUEVO: ESCRIBIR FECHA EN HOJA 'DRIVE P-V' ===
        if 'DRIVE P-V' in hojas:
            hoja_v = wb.sheets['DRIVE P-V']
            # En vez de mandar un string (que Excel dependiendo el locale puede invertir a mes/día),
            # pasamos el objeto de fecha nativo y le forzamos el formato en la celda
            print(f"Escribiendo fecha {fecha_objetivo_date.strftime('%d/%m/%Y')} en celda L3 de la hoja 'DRIVE P-V'...")
            hoja_v.range('L3').value = fecha_objetivo_date
            try:
                hoja_v.range('L3').number_format = 'dd/mm/yyyy'
            except Exception:
                # Fallback por si el Excel en español rechaza 'yyyy' y exige 'aaaa'
                try:
                    hoja_v.range('L3').number_format = 'dd/mm/aaaa'
                except: pass

        # === LIMPIAR RANGO B4:D8 EN HOJA 'DRIVE-Disp.' ===
        if 'DRIVE-Disp.' in hojas:
            hoja_drive_disp = wb.sheets['DRIVE-Disp.']
            print("Limpiando rango B4:D8 en hoja 'DRIVE-Disp.'...")
            hoja_drive_disp.range('B4:D8').clear_contents()
            print("  -> Rango B4:D8 de 'DRIVE-Disp.' limpiado correctamente.")
        else:
            print("Advertencia: No se encontró la hoja 'DRIVE-Disp.' en el libro.")

        # Guardar cambios en el archivo abierto (que es nuestra copia: archivo_madre_nuevo.xlsx)
        app.display_alerts = False
        
        # === ACTUALIZAR TABLAS DINÁMICAS ===
        print("Actualizando todas las tablas dinámicas del libro...")
        try:
            # Desactivar alertas y eventos para que no salten popups
            app.api.DisplayAlerts = False
            app.api.EnableEvents = False
            
            # RefreshAll() actualiza TODAS las tablas dinámicas, conexiones
            # y rangos con nombre dinámicos del libro de una sola vez
            wb.api.RefreshAll()
            app.calculate()
            print("¡Todas las tablas dinámicas actualizadas!")
        except Exception as e:
            print(f"Advertencia al actualizar tablas dinámicas: {e}")
        finally:
            try:
                app.api.EnableEvents = True
            except:
                pass

        print("Guardando y cerrando los cambios en el archivo nuevo...")
        wb.save()
        print("¡Listo! Documento generado y actualizado con exito.")
        exito = True
        return exito
        
    finally:
        # Importante: siempre intentamos cerrar excel y la aplicacion final del código
        # para que no queden procesos residuales colgados consumiendo RAM
        try:
            wb.close()
        except:
            pass
        app.quit()

if __name__ == "__main__":
    import glob
    import re
    
    directorio_base = os.path.dirname(os.path.abspath(__file__))
    
    # Buscar el archivo madre con el patrón "archivo_informe YYYY-MM-DD 06 AM*.xlsx"
    patron_busqueda = os.path.join(directorio_base, "archivo_informe * 06 AM*.xlsx")
    archivos_encontrados = glob.glob(patron_busqueda)
    
    if len(archivos_encontrados) == 0:
        print(f"Error: No se encontró ningún archivo con el patrón 'archivo_informe YYYY-MM-DD 06 AM.xlsx' en {directorio_base}")
    else:
        # Tomamos el primero que encuentre 
        ruta_archivo = archivos_encontrados[0]
        nombre_archivo = os.path.basename(ruta_archivo)
        
        # Extraer la fecha del nombre usando Regex
        match = re.search(r"archivo_informe (\d{4}-\d{2}-\d{2}) 06 AM", nombre_archivo)
        
        if match:
            fecha_str = match.group(1)
            fecha_archivo = datetime.datetime.strptime(fecha_str, "%Y-%m-%d").date()
            fecha_siguiente = fecha_archivo + datetime.timedelta(days=1)
            
            nuevo_nombre = f"archivo_informe {fecha_siguiente.strftime('%Y-%m-%d')} 06 AM.xlsx"
            nueva_ruta = os.path.join(os.path.dirname(ruta_archivo), nuevo_nombre)
            
            print(f"Archivo madre detectado: '{nombre_archivo}' (Fecha: {fecha_str})")
            print(f"Nuevo archivo a generar: '{nuevo_nombre}'")
            print("-" * 50)
            
            resultado = update_excel_with_xlwings(ruta_archivo, nuevo_nombre)
            
            if not resultado:
                if os.path.exists(nueva_ruta):
                    try:
                        os.remove(nueva_ruta)
                        print(f"Archivo temporal borrado: {nuevo_nombre}")
                    except Exception as e:
                        print(f"No se pudo borrar el archivo temporal {nuevo_nombre}: {e}")
        else:
            print(f"Error: El archivo encontrado '{nombre_archivo}' no tiene el formato de fecha correcto ('YYYY-MM-DD').")
