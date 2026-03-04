import os
import xlwings as xw

def update_excel_with_xlwings(filepath, output_filename):
    print(f"Iniciando Excel en segundo plano para procesar: {filepath}")
    
    # Inicia Excel de modo invisible
    app = xw.App(visible=False)
    
    try:
        # Abrir el workbook
        wb = app.books.open(filepath)
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
                
        # 2. Limpiar columnas en 'Levantado' y 'NoLevantado' (C hasta R) desde la fila 2
        hojas_secundarias = ['Levantado', 'NoLevantado']
        for nombre_hoja in hojas_secundarias:
            if nombre_hoja in hojas:
                print(f"Limpiando columnas C hasta R en '{nombre_hoja}'...")
                hoja_sec = wb.sheets[nombre_hoja]
                max_row_sec = hoja_sec.used_range.last_cell.row
                if max_row_sec > 1:
                    rango_str = f"C2:R{max_row_sec}"
                    hoja_sec.range(rango_str).clear_contents()
            else:
                print(f"Advertencia: No se encontró la hoja '{nombre_hoja}' para limpiar.")

        # Guardar como nuevo archivo
        output_path = os.path.join(os.path.dirname(filepath), output_filename)
        
        # Desactivamos alertas para que Excel sobreescriba directamente sin preguntar ni lanzar error de Windows
        app.display_alerts = False
             
        print(f"Guardando como nuevo archivo (sobreescribiendo si existe): {output_path}")
        wb.save(output_path)
        print("¡Listo! Documento generado con exito.")
        
    finally:
        # Importante: siempre intentamos cerrar excel y la aplicacion final del código
        # para que no queden procesos residuales colgados consumiendo RAM
        wb.close()
        app.quit()

if __name__ == "__main__":
    directorio_base = r"c:\Users\nico9\Downloads\APP_nuevoinforme\vistas\informediario\2026-03-03"
    ruta_archivo = os.path.join(directorio_base, "archivo_madre.xlsx")
    
    if os.path.exists(ruta_archivo):
        update_excel_with_xlwings(ruta_archivo, "archivo_madre_nuevo.xlsx")
    else:
        print(f"Error: No se encontro el archivo en {ruta_archivo}")
