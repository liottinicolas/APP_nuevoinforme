---
name: proyecto-documentador
description: Analyzes and documents complex data projects. Read R, Python, SQL, and Jupyter code to generate detailed Markdown documentation with data sources, functionality, and improvement suggestions. Maintains version history and changelog automatically. Use this whenever you need to document your data pipeline, Jupiter notebooks, analytics scripts, or database queries. Perfect for keeping track of project changes, data lineage, and future improvements in a centralized location.
---

# Proyecto Documentador

Una skill para documentar proyectos de datos complejos (R, Python, SQL, Jupyter) manteniendo control de versiones y cambios.

## 🎯 Qué Hace

Esta skill te ayuda a:

1. **Analizar** tu proyecto completo (archivos .py, .r, .sql, .ipynb, .rds, .parquet, .xlsx)
2. **Generar documentación detallada** en Markdown
3. **Organizar** en: documento central + archivos por componente
4. **Rastrear** cambios automáticamente con timestamp
5. **Permitir** versionado manual cuando quieras documentar mejoras
6. **Registrar** fuentes de datos, lógica y mejoras futuras

## 📋 Cómo Usar

### Opción 1: Documentación Completa (Primera vez)
```
/doc-project [ruta-proyecto]
```
Escanea todo el proyecto y genera:
- `README_PROYECTO.md` (documento central)
- `docs/` carpeta con:
  - `data-sources.md` (fuentes de datos)
  - `modules/` (un archivo por módulo/notebook)
  - `changelog.md` (registro de cambios)

### Opción 2: Actualizar Documentación (Después de cambios)
```
/doc-update [ruta-proyecto] --auto
```
Detecta automáticamente cambios y actualiza:
- Documentos afectados
- Changelog con timestamp
- Mejoras sugeridas

### Opción 3: Documentar Manualmente una Mejora
```
/doc-update [ruta-proyecto] --manual "Descripción del cambio"
```
Te permite agregar notas manualmente sobre cambios específicos.

## 📁 Estructura Generada

```
tu-proyecto/
├── README_PROYECTO.md          # Índice central
├── docs/
│   ├── changelog.md            # Historial de cambios
│   ├── data-sources.md         # Todas las fuentes de datos
│   ├── modules/
│   │   ├── notebook-1.md
│   │   ├── script-analisis.md
│   │   ├── queries-db.md
│   │   └── utilities.md
│   └── improvements.md         # Mejoras futuras detectadas
└── .doc-index.json             # Metadata para versionado
```

## 📄 Contenido de Cada Documento

### 1. README_PROYECTO.md (Documento Central)
```markdown
# Proyecto: [Nombre]
Fecha de creación: 2024-01-15
Última actualización: 2024-01-20

## 📊 Resumen Ejecutivo
[Qué hace el proyecto en 2-3 líneas]

## 🗂️ Estructura
[Mapa de archivos y módulos]

## 📈 Flujo de Datos
[De dónde vienen los datos → qué procesamiento → dónde va]

## 🔗 Componentes
- [Nombre notebook/script] - Descripción
- [Otra cosa] - Descripción

## ⚙️ Dependencias
R packages, librerías Python, versiones

## 🚀 Próximas Mejoras
[Del archivo improvements.md]

## 📅 Historial
[Resumen del changelog.md]
```

### 2. modules/[archivo].md
```markdown
# [Nombre Notebook/Script]
Tipo: Jupyter Notebook / Python Script / R Script / SQL Query
Última modificación: 2024-01-20

## 📖 ¿Qué hace?
[Descripción clara de propósito]

## 📊 Entrada (Input)
- Fuentes: [tablas, archivos, APIs]
- Formato: [CSV, Parquet, SQL query, etc]
- Ejemplos: [primeras filas o estructura]

## 🔄 Proceso
[Paso a paso qué hace el código]

### Lógica Principal
\`\`\`python
# Código representativo (sin todo el script)
query = """
SELECT * FROM produccion.tabla
WHERE fecha >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
"""
datos = pd.read_sql(query, conexion)
\`\`\`

## 📤 Salida (Output)
- Genera: [tabla, archivo, reporte]
- Dónde va: [base de datos, carpeta local]
- Formato: [Parquet, CSV, Excel]

## 🔗 Dependencias
- R: ggplot2, dplyr, etc
- Python: pandas, numpy, etc
- Base de datos: produccion.tabla_x

## ⚡ Mejoras Futuras
- [ ] Optimizar query (es lenta)
- [ ] Agregar logging
- [ ] Paralelizar procesamiento

## 📌 Notas
[Consideraciones especiales]
```

### 3. data-sources.md
```markdown
# Fuentes de Datos

## Base de Datos: produccion
- **Host:** [ip/servidor]
- **Esquema:** produccion
- **Tablas principales:**
  - tabla_ventas: [descripción, rows, update frequency]
  - tabla_clientes: [descripción]

## Archivos Locales
- `/data/input/exportación_mensual.xlsx`
- `/data/cache/datos_procesados.parquet`

## APIs Externas
- Endpoint: [url]
- Frecuencia de llamadas
- Rate limits

## Datalake / S3 / Cloud
- Ubicación
- Estructura de carpetas
```

### 4. improvements.md
```markdown
# Mejoras Futuras Detectadas

Generadas automáticamente en cada análisis.

## 🔴 Críticas (Hacer pronto)
- [ ] Query N1 tarda 15 min (optimizar)
- [ ] Falta manejo de errores en script_analisis.py

## 🟡 Importantes
- [ ] Documentar funciones R sin docstring
- [ ] Agregar unit tests

## 🟢 Nice to Have
- [ ] Cache de resultados
- [ ] Visualizaciones interactivas
```

### 5. changelog.md
```markdown
# Changelog

## 2024-01-20 | v1.2.0
**Cambios automáticos detectados:**
- ✏️ Modificado: script_analisis.py
  - Líneas: 45-52 | Nueva lógica de validación
  - Impacto: mejora precisión 3%
  
- ✏️ Modificado: query_ventas.sql
  - Líneas: 1-10 | Filtro agregado
  - Impacto: reduce tiempo de ejecución

**Cambios manuales:**
- 📝 Nota: "Optimización exitosa de query N1"

---

## 2024-01-15 | v1.1.0
**Automático:**
- ➕ Nuevo: notebook_exploratorio.ipynb
```

## 🔄 Sistema de Versionado

### Automático (cada vez que ejecutas /doc-update --auto)
- Detecta cambios en archivos
- Registra líneas modificadas
- Estima impacto
- Actualiza timestamp

### Manual (cuando quieres anotar algo importante)
```
/doc-update --manual "Optimización completada: query ahora 50% más rápida"
```
Esto agrega una nota al changelog con tu contexto.

## 💡 Casos de Uso Reales

### Caso 1: Documentar nuevo notebook
```
/doc-project .
# Genera docs/modules/nuevo_analisis.md con:
# - Qué datos extrae de producción
# - Qué transformaciones hace
# - Dónde guarda el output
# - Mejoras sugeridas (validar datos, etc)
```

### Caso 2: Después de optimizar una query
```
/doc-update . --manual "Query optimizada: índice agregado en fecha. 60% más rápida"
# Actualiza:
# - El archivo del módulo (refleja cambios)
# - Changelog (registra mejora)
# - improvements.md (quita de la lista)
```

### Caso 3: Auditoria completa
```
/doc-update . --auto
# Genera reporte completo de:
# - Qué cambió desde última documentación
# - Impacto estimado
# - Nuevos riesgos o mejoras
```

## 🛠️ Opciones Avanzadas

### Excluir archivos
```
/doc-project . --ignore "venv,__pycache__,.cache"
```

### Solo documentar cambios (sin re-hacer todo)
```
/doc-update . --changes-only
```

### Generar reporte en HTML también
```
/doc-update . --html
# Crea docs/index.html con versión navegable
```

## 📊 Metadata Automático

El skill mantiene un archivo `.doc-index.json` que rastrea:

```json
{
  "last_updated": "2024-01-20T14:30:00Z",
  "files_documented": 12,
  "version": "1.2.0",
  "changes_this_cycle": [
    {
      "file": "script_analisis.py",
      "lines_changed": "45-52",
      "timestamp": "2024-01-20T14:00:00Z",
      "auto_detected": true,
      "impact": "medium"
    }
  ],
  "data_sources": ["produccion.ventas", "local/datos.parquet"],
  "dependencies": ["pandas", "numpy", "dplyr"]
}
```

Esto permite:
- Saber exactamente qué cambió y cuándo
- Rastrear dependencias
- Generar auditorías
- Comparar versiones

## ⚙️ Lo que el Skill Detecta Automáticamente

### En Python/R
- Imports/librerías (dependencias)
- Funciones y su propósito
- Conexiones a base de datos
- Archivos leídos/escritos

### En SQL
- Tablas consultadas
- JOINs y transformaciones
- Vistas creadas

### En Jupyter
- Celdas de código y markdown
- Visualizaciones generadas
- Datos importados/exportados

## 📌 Tips

1. **Ejecuta `/doc-update . --auto` al final de cada sprint** para mantener docs frescos
2. **Usa `--manual` cuando hagas optimizaciones grandes** para que quede registrado
3. **Revisa `improvements.md` regularmente** para prioridades futuras
4. **Git-friendly**: Los .md se versionan bien, `.doc-index.json` es el metadata

## Ejemplo Completo: Tu Primer Documento

Cuando ejecutas:
```
/doc-project /ruta/a/mi/proyecto
```

Obtienes una estructura lista para:
- **Compartir** con el equipo (README central)
- **Entender** el flujo (data-sources + modules)
- **Mejorar** (improvements.md)
- **Auditar** cambios (changelog)
- **Versionear** en Git (todo es Markdown)

¡Listo para documentar! 🚀
