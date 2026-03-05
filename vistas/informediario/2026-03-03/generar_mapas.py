import os
import glob
import re
import datetime
import pandas as pd

def generar_atraso_csv():
    print("Iniciando script de generación de Atraso CSV...")
    directorio_base = os.path.dirname(os.path.abspath(__file__))
    
    # Buscar el archivo madre más reciente con el patrón "archivo_informe YYYY-MM-DD 06 AM*.xlsx"
    patron_busqueda = os.path.join(directorio_base, "archivo_informe * 06 AM*.xlsx")
    archivos_encontrados = glob.glob(patron_busqueda)
    
    if len(archivos_encontrados) == 0:
        print(f"Error: No se encontró ningún archivo con el patrón 'archivo_informe YYYY-MM-DD 06 AM.xlsx' en {directorio_base}")
        return
        
    # Ordenamos por nombre para agarrar el de fecha mayor si hay múltiples
    archivos_encontrados.sort(reverse=True)
    ruta_archivo = archivos_encontrados[0]
    nombre_archivo = os.path.basename(ruta_archivo)
    print(f"Detectado archivo: {nombre_archivo}")
    
    # Extraer la fecha del nombre usando Regex para nombrar el CSV de salida
    match = re.search(r"archivo_informe (\d{4}-\d{2}-\d{2}) 06 AM", nombre_archivo)
    
    if not match:
        print(f"Error: El archivo encontrado '{nombre_archivo}' no tiene el formato de fecha correcto ('YYYY-MM-DD').")
        return
        
    fecha_str = match.group(1)
    
    # Declarar ruta del output en la carpeta Mapas
    carpeta_mapas = os.path.join(directorio_base, "Mapas")
    if not os.path.exists(carpeta_mapas):
        print(f"Creando directorio Mapas en {carpeta_mapas}")
        os.makedirs(carpeta_mapas)
        
    ruta_salida = os.path.join(carpeta_mapas, f"Atraso {fecha_str}.csv")
    print(f"Generando archivo de salida en: {ruta_salida}")
    
    try:
        # Cargar la Hoja HOY. Usamos usecols para traer solo las necesarias y no saturar la memoria
        # Suponiendo estructura común: gid y Acumulacion_general. Identificaremos por nombre de columna
        print("Cargando la hoja 'Hoy' en pandas...")
        # Leemos solo la primera fila (titulos) para identificar los indices de 'gid' y 'Acumulacion_general'
        # o, más seguro, leer todo como dataframe e invocar las columnas por nombre
        df_hoy = pd.read_excel(ruta_archivo, sheet_name='Hoy')
        
        columnas_disponibles = [str(c).lower().strip() for c in df_hoy.columns]
        
        # Buscar mapeos insensibles a mayúsculas
        col_gid = next((c for c in df_hoy.columns if str(c).lower().strip() == 'gid'), None)
        col_acumulacion = next((c for c in df_hoy.columns if str(c).lower().strip() == 'acumulacion_general'), None)
        col_estado = next((c for c in df_hoy.columns if str(c).lower().strip() == 'estado'), None)

        if not col_gid or not col_acumulacion or not col_estado:
             print(f"Error Crítico: No se pudo encontrar las columnas 'gid', 'Acumulacion_general' o 'Estado' en la hoja Hoy.")
             print(f"Columnas detectadas: {list(df_hoy.columns)}")
             return
             
        # 0. Filtrar por Estado == en blanco (NaN o string vacío)
        print("Filtrando filas donde 'Estado' está en blanco...")
        df_hoy = df_hoy[df_hoy[col_estado].isna() | (df_hoy[col_estado].astype(str).str.strip() == '')]
             
        # ==========================================
        # 1. EXPORTAR: ATRASOS (.csv)
        # ==========================================
        # Quedarse con las columnas requeridas para el CSV
        df_atraso = df_hoy[[col_gid, col_acumulacion]].copy()
        
        # Limpiar posibles nulos/NaN
        df_atraso = df_atraso.dropna(subset=[col_gid, col_acumulacion])
        
        # Asegurar tipo numérico
        df_atraso[col_acumulacion] = pd.to_numeric(df_atraso[col_acumulacion], errors='coerce').fillna(0)
        
        # A los valores mayores a 6, asignarles 6 (Clamping)
        print("Aplicando tope máximo de 6 a Acumulacion_general...")
        df_atraso.loc[df_atraso[col_acumulacion] > 6, col_acumulacion] = 6
        
        # Formatear a Int (para coincidir con CSV de ejemplo)
        df_atraso[col_acumulacion] = df_atraso[col_acumulacion].astype(int)
        try:
             df_atraso[col_gid] = df_atraso[col_gid].astype(int)
        except:
             pass # Si GID tuviese letras (no es común), ignorar int cast.
        
        # Ordenarlos de mayor a menor
        print("Ordenando datos de mayor a menor por Acumulacion_general...")
        df_atraso = df_atraso.sort_values(by=col_acumulacion, ascending=False)
        
        ruta_salida_atrasos = os.path.join(carpeta_mapas, f"Atraso {fecha_str}.csv")
        print("Escribiendo CSV destino de Atrasos (separador ';')...")
        df_atraso.to_csv(ruta_salida_atrasos, sep=';', index=False, encoding='utf-8')
        print(f"¡Éxito! CSV Atrasos guardado correctamente con {len(df_atraso)} registros.")

        # ==========================================
        # 2. EXPORTAR: UNA (.csv)
        # ==========================================
        col_frecuencia = next((c for c in df_hoy.columns if str(c).lower().strip() == 'frecuencia'), None)
        
        if not col_frecuencia:
             print(f"Error Crítico: No se pudo encontrar la columna 'Frecuencia' en la hoja Hoy. Omitiendo generación UNA.")
        else:
             print("\nGenerando archivo de salida UNA...")
             df_una = df_hoy[[col_gid, col_frecuencia, col_acumulacion]].copy()
             df_una = df_una.dropna(subset=[col_gid, col_frecuencia, col_acumulacion])
             
             # Asegurar algebra numerica
             df_una[col_frecuencia] = pd.to_numeric(df_una[col_frecuencia], errors='coerce').fillna(0)
             df_una[col_acumulacion] = pd.to_numeric(df_una[col_acumulacion], errors='coerce').fillna(0)
             
             # Calculo Base
             df_una['Valor_UNA'] = (df_una[col_frecuencia] * df_una[col_acumulacion]) / 7.0 * 100.0
             
             # Mapeo a categorías del 1 al 5
             def categorizar_una(valor):
                 if valor <= 100: return 1
                 elif 100 < valor <= 130: return 2
                 elif 130 < valor <= 150: return 3
                 elif 150 < valor <= 170: return 4
                 else: return 5
                 
             df_una['RANGO UNAP'] = df_una['Valor_UNA'].apply(categorizar_una)
             
             # Guardar con formato: GID;RANGO UNAP
             df_una_export = df_una[[col_gid, 'RANGO UNAP']].copy()
             
             try: df_una_export[col_gid] = df_una_export[col_gid].astype(int)
             except: pass
             
             # Ordenar UNA por GID ascendente como el ejemplo
             df_una_export = df_una_export.sort_values(by=col_gid, ascending=True)
             
             ruta_salida_una = os.path.join(carpeta_mapas, f"UNA {fecha_str}.csv")
             print(f"Escribiendo CSV destino de UNA...")
             df_una_export.to_csv(ruta_salida_una, sep=';', index=False, encoding='utf-8')
             print(f"¡Éxito! CSV UNA guardado correctamente con {len(df_una_export)} registros.")

        # ==========================================
        # 3. EXPORTAR: REPETIDOS (.csv)
        # ==========================================
        print("\nGenerando archivo de salida Repetidos ('Repite')...")
        # Ya tenemos df_hoy filtrado por Estado == en blanco.
        
        # Filtrar df_hoy por Acumulacion_general == 1 y Frecuencia != 7
        df_hoy_rep = df_hoy.copy()
        
        # Validar q existan las 3 columnas
        if col_gid and col_acumulacion and col_frecuencia:
            df_hoy_rep[col_acumulacion] = pd.to_numeric(df_hoy_rep[col_acumulacion], errors='coerce')
            df_hoy_rep[col_frecuencia] = pd.to_numeric(df_hoy_rep[col_frecuencia], errors='coerce')
            
            df_hoy_rep = df_hoy_rep[(df_hoy_rep[col_acumulacion] == 1) & (df_hoy_rep[col_frecuencia] != 7)]
            
            # Cargar hoja Ayer
            try:
                print("Cargando la hoja 'Ayer' en pandas para comparación...")
                df_ayer = pd.read_excel(ruta_archivo, sheet_name='Ayer')
                
                col_gid_ayer = next((c for c in df_ayer.columns if str(c).lower().strip() == 'gid'), None)
                col_acum_ayer = next((c for c in df_ayer.columns if str(c).lower().strip() == 'acumulacion_general'), None)
                
                if col_gid_ayer and col_acum_ayer:
                    # Filtar Ayer por Acumulacion_general == 1
                    df_ayer[col_acum_ayer] = pd.to_numeric(df_ayer[col_acum_ayer], errors='coerce')
                    df_ayer_rep = df_ayer[df_ayer[col_acum_ayer] == 1]
                    
                    # Intersecar ambos DataFrames por GID para obtener "Los que están en los dos"
                    match_gids = pd.merge(
                        df_hoy_rep[[col_gid]], 
                        df_ayer_rep[[col_gid_ayer]], 
                        left_on=col_gid, 
                        right_on=col_gid_ayer, 
                        how='inner'
                    )
                    
                    # Preparar exportacion
                    df_repite_export = match_gids[[col_gid]].copy()
                    df_repite_export['Repite'] = 1
                    
                    try: df_repite_export[col_gid] = df_repite_export[col_gid].astype(int)
                    except: pass
                    
                    df_repite_export = df_repite_export.sort_values(by=col_gid, ascending=True)
                    
                    ruta_salida_repite = os.path.join(carpeta_mapas, f"Repite {fecha_str}.csv")
                    print("Escribiendo CSV destino de Repite...")
                    df_repite_export.to_csv(ruta_salida_repite, sep=';', index=False, encoding='utf-8')
                    print(f"¡Éxito! CSV Repetidos guardado correctamente con {len(df_repite_export)} registros.")
                else:
                    print("Error: No se encontró la columna GID o Acumulacion_general en la hoja 'Ayer'.")
            except Exception as e_ayer:
                print(f"Error procesando la hoja Ayer: {e_ayer}")
        else:
            print("Error: Columnas faltantes en 'Hoy' para procesar Repetidos.")

    except Exception as e:
        print(f"Se produjo un error al procesar el Excel: {e}")

if __name__ == "__main__":
    generar_atraso_csv()
