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
    
    # Inicia Excel de modo invisible
    app = xw.App(visible=False)
    
    try:
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
                                # Excel almacena fechas como número de días desde 1899-12-30
                                fecha_viaje_dt = datetime.datetime(1899, 12, 30) + datetime.timedelta(days=val_c2)
                            elif isinstance(val_c2, datetime.datetime):
                                fecha_viaje_dt = val_c2
                            
                            if fecha_viaje_dt:
                                print(f"Fecha extraída ('dia_viaje') de {nombre_hoja} en C2: {fecha_viaje_dt.strftime('%d/%m/%Y')} (Valor original: {val_c2})")
                        except Exception as e:
                            print(f"Error al transformar la fecha en {nombre_hoja}!C2: {e}")

        # === FILTRAR RDS CON FECHA + 1 DIA ===
        df_ubicaciones_filtrado = None
        df_llenado_filtrado = None
        
        if fecha_viaje_dt:
            fecha_objetivo = fecha_viaje_dt + datetime.timedelta(days=1)
            fecha_objetivo_date = fecha_objetivo.date()
            print(f"La fecha objetivo para filtrar RDS es: {fecha_objetivo_date.strftime('%Y-%m-%d')}")
            
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
                    print(f"  -> historico_ubicaciones filtrado: {len(df_ubicaciones_filtrado)} registros encontrados para {fecha_objetivo_date}.")
                else:
                    print(f"Advertencia: No se encontro el archivo de ubicaciones en {ruta_ubicaciones}")
                
                print("Cargando y filtrando historico_llenadoGol.rds...")
                if os.path.exists(ruta_llenado):
                    df_llenado = pyreadr.read_r(ruta_llenado)[None]
                    df_llenado['Fecha_dt'] = pd.to_datetime(df_llenado['Fecha'], dayfirst=False).dt.date
                    df_llenado_filtrado = df_llenado[df_llenado['Fecha_dt'] == fecha_objetivo_date].copy()
                    print(f"  -> historico_llenado filtrado: {len(df_llenado_filtrado)} registros encontrados para {fecha_objetivo_date}.")
                else:
                    print(f"Advertencia: No se encontro el archivo de llenado en {ruta_llenado}")
                    
            except Exception as e:
                print(f"Error al cargar o filtrar archivos RDS: {e}")

        # === NUEVO: ESCRIBIR DATOS DE UBICACIONES EN HOJA 'Hoy' ===
        if df_ubicaciones_filtrado is not None and not df_ubicaciones_filtrado.empty:
            print("Escribiendo datos de ubicaciones en columnas A,B,I,J,K,L,M de 'Hoy'...")
            # Usar objetos pandas DateFrame directo con las opciones de xlwings para evitar errores de conversion o de dimensiones
            df_AB = df_ubicaciones_filtrado[['gid', 'Circuito']].fillna("")
            df_I_M = df_ubicaciones_filtrado[['Posicion', 'Estado', 'Calle', 'Numero', 'Observaciones']].fillna("")
            
            # Opciones de volcado: omitir el index de pandas y el header (nombre de columna).
            hoja_hoy.range('A2').options(index=False, header=False).value = df_AB
            hoja_hoy.range('I2').options(index=False, header=False).value = df_I_M
            
            cant_filas_nuevas = len(df_AB)
            print(f"  -> Se escribieron {cant_filas_nuevas} filas en la hoja 'Hoy'.")

            # === AJUSTE DE  FORMULAS (C HASTA H) EN HOJA 'Hoy' ===
            print("Ajustando formulas en columnas C hasta H de 'Hoy'...")
            ultimo_row_formulas = hoja_hoy.range('C' + str(hoja_hoy.cells.last_cell.row)).end('up').row
            
            # Si no hay fórmulas o si devuelve un numero erróneo al llegar hasta arriba (Fila 1 con titulo)
            if ultimo_row_formulas < 2:
                ultimo_row_formulas = 2
                
            fila_final_esperada = 1 + cant_filas_nuevas
            
            if max_row_hoy > fila_final_esperada:
                # Si en base al anterior conteo de "Hoy" original hay más filas que lo copiado, limpiar resto de C:H
                filas_sobrantes = max_row_hoy - fila_final_esperada
                print(f"  -> Borrando formulas sobrantes abajo de la fila {fila_final_esperada} (hasta {max_row_hoy}).")
                rango_barrer = f'C{fila_final_esperada + 1}:H{max_row_hoy}'
                hoja_hoy.range(rango_barrer).clear_contents()
                # Limpiar N:P
                rango_barrer_np = f'N{fila_final_esperada + 1}:P{max_row_hoy}'
                hoja_hoy.range(rango_barrer_np).clear_contents()
                
            elif ultimo_row_formulas < fila_final_esperada:
                # Si la fórmula llega a menos que nuestra data nueva, extender fórmula existente (idealmente de fila 2 en adelante)
                origen_row = ultimo_row_formulas if ultimo_row_formulas >= 2 else 2
                print(f"  -> Extendiendo formulas desde la fila {origen_row} hasta {fila_final_esperada}.")
                rango_origen = hoja_hoy.range(f'C{origen_row}:H{origen_row}')
                rango_destino = hoja_hoy.range(f'C{origen_row}:H{fila_final_esperada}')
                rango_origen.api.AutoFill(rango_destino.api, 0)
                
            # Ajustar Rango N:P
            ultimo_row_formulas_np = hoja_hoy.range('N' + str(hoja_hoy.cells.last_cell.row)).end('up').row
            if ultimo_row_formulas_np < 2:
                ultimo_row_formulas_np = 2
                
            if ultimo_row_formulas_np < fila_final_esperada:
                origen_row_np = ultimo_row_formulas_np if ultimo_row_formulas_np >= 2 else 2
                rango_origen_np = hoja_hoy.range(f'N{origen_row_np}:P{origen_row_np}')
                rango_destino_np = hoja_hoy.range(f'N{origen_row_np}:P{fila_final_esperada}')
                rango_origen_np.api.AutoFill(rango_destino_np.api, 0)

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
                
            # 1. 'Levantado' (S)
            df_lev = df_destino[df_destino['Levantado'] == 'S'].fillna("")
            cant_lev = len(df_lev)
            if 'Levantado' in hojas and cant_lev > 0:
                print(f"Escribiendo {cant_lev} filas en 'Levantado' desde C2...")
                hoja_lev = wb.sheets['Levantado']
                hoja_lev.range('C2').options(index=False, header=False).value = df_lev
                
                # Ajuste de fórmulas en A:B y limpieza hacia abajo para 'Levantado'
                max_row_lev = hoja_lev.used_range.last_cell.row
                fila_final_lev = 1 + cant_lev
                
                if max_row_lev > fila_final_lev:
                    filas_sobrantes_lev = max_row_lev - fila_final_lev
                    hoja_lev.range(f'A{fila_final_lev + 1}:Q{max_row_lev}').clear_contents()
                elif fila_final_lev > 2:
                    # Extender formulas A:B (O cualquier otra q quede)
                    ultimo_row_A_lev = hoja_lev.range('A' + str(max_row_lev)).end('up').row
                    origen_row_lev = ultimo_row_A_lev if ultimo_row_A_lev >= 2 else 2
                    if origen_row_lev < fila_final_lev:
                        rango_origen_lev = hoja_lev.range(f'A{origen_row_lev}:B{origen_row_lev}')
                        rango_destino_lev = hoja_lev.range(f'A{origen_row_lev}:B{fila_final_lev}')
                        rango_origen_lev.api.AutoFill(rango_destino_lev.api, 0)
                        
            # 2. 'NoLevantado' (N o NA)
            df_nolev = df_destino[df_destino['Levantado'].isin(['N', '']) | df_destino['Levantado'].isna()].fillna("")
            cant_nolev = len(df_nolev)
            if 'NoLevantado' in hojas and cant_nolev > 0:
                print(f"Escribiendo {cant_nolev} filas en 'NoLevantado' desde C2...")
                hoja_nolev = wb.sheets['NoLevantado']
                hoja_nolev.range('C2').options(index=False, header=False).value = df_nolev
                
                # Ajuste de fórmulas en A:B y limpieza hacia abajo para 'NoLevantado'
                max_row_nolev = hoja_nolev.used_range.last_cell.row
                fila_final_nolev = 1 + cant_nolev
                
                if max_row_nolev > fila_final_nolev:
                    filas_sobrantes_nolev = max_row_nolev - fila_final_nolev
                    hoja_nolev.range(f'A{fila_final_nolev + 1}:Q{max_row_nolev}').clear_contents()
                elif fila_final_nolev > 2:
                    # Extender formulas A:B 
                    ultimo_row_A_nolev = hoja_nolev.range('A' + str(max_row_nolev)).end('up').row
                    origen_row_nolev = ultimo_row_A_nolev if ultimo_row_A_nolev >= 2 else 2
                    if origen_row_nolev < fila_final_nolev:
                        rango_origen_nolev = hoja_nolev.range(f'A{origen_row_nolev}:B{origen_row_nolev}')
                        rango_destino_nolev = hoja_nolev.range(f'A{origen_row_nolev}:B{fila_final_nolev}')
                        rango_origen_nolev.api.AutoFill(rango_destino_nolev.api, 0)

        # Guardar cambios en el archivo abierto (que es nuestra copia: archivo_madre_nuevo.xlsx)
        app.display_alerts = False
        print("Guardando y cerrando los cambios en el archivo nuevo...")
        wb.save()
        print("¡Listo! Documento generado y actualizado con exito.")
        
    finally:
        # Importante: siempre intentamos cerrar excel y la aplicacion final del código
        # para que no queden procesos residuales colgados consumiendo RAM
        wb.close()
        app.quit()

if __name__ == "__main__":
    directorio_base = os.path.dirname(os.path.abspath(__file__))
    ruta_archivo = os.path.join(directorio_base, "archivo_madre.xlsx")
    
    if os.path.exists(ruta_archivo):
        update_excel_with_xlwings(ruta_archivo, "archivo_madre_nuevo.xlsx")
    else:
        print(f"Error: No se encontro el archivo en {ruta_archivo}")
