# ==============================================================================
# barrido.R
# Actualización de capas de Barrido desde PostgreSQL/QGIS de la IMM
# ==============================================================================

library(here)
library(dplyr)

# 1. Cargar funciones de conexión y actualización
#    Sourcing conexionPOSTGRES.R defines conectar_postgres, actualizar_capa_postgres, etc.
source(here("db/POSTGRES/conexionPOSTGRES.R"))

# Validar que las funciones necesarias existan
if (!exists("conectar_postgres") || !exists("actualizar_capa_postgres") || !exists("listar_tablas_postgres") || !exists("cargar_capas_barrido")) {
  stop("No se pudieron cargar las funciones de conexionPOSTGRES.R")
}

# 2. Función para unificar las capas cargadas
#' Une una lista de capas/data frames en un único data frame o sf object.
#'
#' Agrega una columna "fuente" con el nombre de la capa y llena con NA 
#' aquellas columnas que no estén presentes en el objeto original.
#'
#' @param lista_capas Lista nombrada de data frames u objetos sf.
#' @return Un único data frame o sf object unificado.
unificar_capas_barrido <- function(lista_capas) {
  if (length(lista_capas) == 0) return(NULL)
  
  # Filtrar elementos nulos
  lista_capas <- lista_capas[!sapply(lista_capas, is.null)]
  if (length(lista_capas) == 0) return(NULL)
  
  # 1. Estandarizar nombre de columna de geometría a "geometry" y harmonizar CRS de objetos sf
  is_sf <- sapply(lista_capas, inherits, "sf")
  if (any(is_sf)) {
    # Primero: Estandarizar el nombre de la columna de geometría a "geometry"
    for (i in which(is_sf)) {
      df <- lista_capas[[i]]
      geom_col <- attr(df, "sf_column")
      if (geom_col != "geometry") {
        names(df)[names(df) == geom_col] <- "geometry"
        attr(df, "sf_column") <- "geometry"
        lista_capas[[i]] <- df
      }
    }
    
    # Segundo: Buscar el primer CRS válido (no NA) y transformar los demás
    all_crs <- lapply(lista_capas[is_sf], sf::st_crs)
    is_valid_crs <- !sapply(all_crs, is.na)
    
    if (any(is_valid_crs)) {
      first_valid_idx <- which(is_sf)[which(is_valid_crs)[1]]
      target_crs <- sf::st_crs(lista_capas[[first_valid_idx]])
      
      for (i in which(is_sf)) {
        current_crs <- sf::st_crs(lista_capas[[i]])
        if (is.na(current_crs)) {
          message("🌐 CRS faltante en '", names(lista_capas)[i], "'. Asignando el CRS de '", names(lista_capas)[first_valid_idx], "'...")
          lista_capas[[i]] <- sf::st_set_crs(lista_capas[[i]], target_crs)
        } else if (current_crs != target_crs) {
          message("🌐 Mismatch de CRS: Transformando '", names(lista_capas)[i], 
                  "' al CRS de '", names(lista_capas)[first_valid_idx], "'...")
          lista_capas[[i]] <- sf::st_transform(lista_capas[[i]], target_crs)
        }
      }
    } else {
      message("⚠️ Ninguna capa de la lista tiene un CRS válido asignado. Intentando unir sin transformar.")
    }
  }
  
  # 2. Identificar todas las columnas y sus clases en cada data frame
  col_info <- list()
  for (nm in names(lista_capas)) {
    df <- lista_capas[[nm]]
    col_names <- colnames(df)
    
    # Obtener columna de geometría si es un objeto sf
    geom_col <- if (inherits(df, "sf")) attr(df, "sf_column") else ""
    
    for (col in col_names) {
      if (col == geom_col) next # Ignorar columna de geometría sf
      
      cl <- class(df[[col]])[1] # Tomar la clase principal
      if (is.null(col_info[[col]])) {
        col_info[[col]] <- list(cl)
      } else {
        col_info[[col]] <- unique(c(col_info[[col]], cl))
      }
    }
  }
  
  # Determinar cuáles columnas tienen clases en conflicto
  conflict_cols <- names(col_info)[sapply(col_info, length) > 1]
  
  # Coercer columnas en conflicto a character
  if (length(conflict_cols) > 0) {
    message("⚠️ Conflictos de tipo detectados para: ", paste(conflict_cols, collapse = ", "), ". Convirtiendo a character para unificar...")
    lista_capas <- lapply(lista_capas, function(df) {
      cols_to_convert <- intersect(conflict_cols, colnames(df))
      if (length(cols_to_convert) > 0) {
        for (col in cols_to_convert) {
          df[[col]] <- as.character(df[[col]])
        }
      }
      df
    })
  }
  
  # bind_rows une las filas, añade la columna .id ("fuente")
  # y rellena automáticamente con NA las columnas faltantes.
  res <- dplyr::bind_rows(lista_capas, .id = "fuente")
  
  # Si había objetos sf pero se perdió la clase sf en la unión, la restauramos
  if (any(is_sf) && !inherits(res, "sf")) {
    res <- sf::st_as_sf(res, sf_column_name = "geometry")
  }
  
  # 3. Unificar (coalescer) nom_calle/calle y TRAMO/tramo
  # Asegurar que todas las columnas de interés existan
  columnas_interes <- c("nom_calle", "calle", "TRAMO", "tramo")
  for (col in columnas_interes) {
    if (!col %in% colnames(res)) {
      res[[col]] <- NA
    }
  }
  
  # Convertir cadenas vacías o espacios en blanco a NA para que coalesce funcione correctamente
  for (col in columnas_interes) {
    vals <- res[[col]]
    vals[is.na(vals) | trimws(as.character(vals)) == ""] <- NA
    res[[col]] <- vals
  }
  
  # Coalescer columnas prefiriendo nom_calle/TRAMO si están presentes
  res$calle_unida <- dplyr::coalesce(as.character(res$nom_calle), as.character(res$calle))
  res$tramo_unido <- dplyr::coalesce(as.character(res$TRAMO), as.character(res$tramo))
  
  # Reemplazar con las versiones unificadas
  res$calle <- res$calle_unida
  res$tramo <- res$tramo_unido
  
  # Asignar Responsable: "IM" o "Municipio"
  res$Responsable <- dplyr::case_when(
    grepl("IM", res$fuente, ignore.case = TRUE) ~ "IM",
    grepl("avenidas_barrido_mecanico", res$fuente, ignore.case = TRUE) ~ "IM",
    TRUE ~ "Municipio"
  )
  
  # Si existe la columna 'responsabl', refinar con ella
  if ("responsabl" %in% colnames(res)) {
    idx_intendencia <- !is.na(res$responsabl) & tolower(as.character(res$responsabl)) == "intendencia"
    res$Responsable[idx_intendencia] <- "IM"
    idx_municipio <- !is.na(res$responsabl) & tolower(as.character(res$responsabl)) == "municipio"
    res$Responsable[idx_municipio] <- "Municipio"
  }
  
  # Asignar Municipio geográficamente con la capa de municipios de WFS
  municipios <- tryCatch({
    wfs_url <- "https://montevideo.gub.uy/app/geoserver/mapstore-tematicas/zon_v_sig_municipios/ows?service=WFS&version=1.0.0&request=GetFeature&typeName=mapstore-tematicas:zon_v_sig_municipios"
    mun <- sf::st_read(wfs_url, quiet = TRUE)
    if (is.na(sf::st_crs(mun))) {
      sf::st_crs(mun) <- 32721
    }
    sf::st_transform(mun, sf::st_crs(res))
  }, error = function(e) {
    message("⚠️ No se pudo descargar la capa de municipios desde WFS: ", e$message)
    NULL
  })
  
  if (!is.null(municipios)) {
    # Desactivar temporalmente s2 para evitar errores de geometría inválida en coordenadas esféricas
    old_s2 <- sf::sf_use_s2(FALSE)
    on.exit(sf::sf_use_s2(old_s2), add = TRUE)
    
    municipios <- sf::st_make_valid(municipios)
    
    # Usar st_centroid para evitar que límites dupliquen filas en st_intersects
    suppressWarnings({
      centroids <- sf::st_centroid(sf::st_geometry(res))
    })
    indices <- sf::st_intersects(centroids, municipios)
    municipio_idx <- sapply(indices, function(x) if (length(x) > 0) x[1] else NA)
    mun_letras <- municipios$municipio[municipio_idx]
    res$Municipio <- ifelse(!is.na(mun_letras), as.character(mun_letras), NA_character_)
  } else {
    # Fallback a mapeo de nombres de capas si falla la conexión WFS
    res$Municipio <- dplyr::case_when(
      grepl("municipio_a|_[Aa]($|_)", res$fuente) ~ "A",
      grepl("municipio_b|_[Bb]($|_)", res$fuente) ~ "B",
      grepl("municipio_c|_[Cc]($|_)", res$fuente) ~ "C",
      grepl("municipio_ch|_[Cc][Hh]($|_)", res$fuente) ~ "CH",
      grepl("municipio_d|_[Dd]($|_)", res$fuente) ~ "D",
      grepl("municipio_e|_[Ee]($|_)", res$fuente) ~ "E",
      grepl("municipio_f|_[Ff]($|_)", res$fuente) ~ "F",
      grepl("municipio_g|_[Gg]($|_)", res$fuente) ~ "G",
      TRUE ~ NA_character_
    )
  }
  
  res$Tipo_barrido <- dplyr::case_when(
    grepl("papeleo", res$fuente, ignore.case = TRUE) ~ "Papeleo",
    grepl("mecanico|mec_nico", res$fuente, ignore.case = TRUE) ~ "Mecánico",
    grepl("manual", res$fuente, ignore.case = TRUE) ~ "Manual",
    grepl("avenida", res$fuente, ignore.case = TRUE) ~ "Mecánico",
    TRUE ~ "Manual"
  )
  
  # Quedarse únicamente con las columnas finales deseadas
  geom_col_active <- if (inherits(res, "sf")) attr(res, "sf_column") else "geometry"
  desired_cols <- c("fuente", "calle", "tramo", "Responsable", "Municipio", "Tipo_barrido", geom_col_active)
  res <- res[, desired_cols, drop = FALSE]
  
  return(res)
}





# 2. Conectar a PostgreSQL
message("Conectando a la base de datos PostgreSQL...")
con <- tryCatch(
  conectar_postgres(),
  error = function(e) {
    stop("Error al conectar a PostgreSQL: ", e$message)
  }
)

# Asegurar desconexión al finalizar el script o si ocurre un error
on.exit({
  if (exists("con") && DBI::dbIsValid(con)) {
    message("Cerrando la conexión a la base de datos...")
    DBI::dbDisconnect(con)
  }
})

# 3. Obtener el listado de tablas de la base de datos
message("Obteniendo listado de tablas...")
tablas <- listar_tablas_postgres(con)

# 4. Filtrar las capas de barrido, papeleo y avenidas
#    Buscamos capas en el esquema 'public' que contengan 'barrido', 'papeleo' o 'avenida' (case-insensitive)
capas_filtradas <- tablas %>%
  filter(
    table_schema == "public",
    grepl("barrido|papeleo|avenida", table_name, ignore.case = TRUE)
  ) %>%
  pull(table_name)

if (length(capas_filtradas) == 0) {
  message("No se encontraron capas que coincidan con 'barrido|papeleo|avenida'.")
} else {
  message("Se encontraron ", length(capas_filtradas), " capas a actualizar:")
  print(capas_filtradas)
  
  # 5. Actualizar cada capa
  for (capa in capas_filtradas) {
    message("\n--- Actualizando capa: ", capa, " ---")
    tryCatch({
      actualizar_capa_postgres(con = con, tabla = capa, schema = "public")
      message("✅ Capa '", capa, "' actualizada con éxito.")
    }, error = function(e) {
      message("❌ Error al actualizar la capa '", capa, "': ", e$message)
    })
  }
}

message("\nProceso de actualización finalizado.")

# ==============================================================================
# EJEMPLO DE USO DE cargar_capas_barrido y unificar_capas_barrido:
# ==============================================================================
# 1. Para cargar las capas locales en formato RDS (por defecto):
capas_barrido_rds <- cargar_capas_barrido(formato = "RDS")
message("Capas cargadas desde RDS: ", paste(names(capas_barrido_rds), collapse = ", "))

# 2. Para unificar todas las capas de la lista en un único data frame:
df_barrido_unido <- unificar_capas_barrido(capas_barrido_rds)
if (!is.null(df_barrido_unido)) {
  message("Filas totales en el df unificado: ", nrow(df_barrido_unido))
  print(head(df_barrido_unido))
  
  # 3. Guardar el dataframe unificado en formato GeoParquet para JupyterHub/Python
  ruta_parquet <- here("scripts/barrido/db/df_barrido_unido.parquet")
  dir.create(dirname(ruta_parquet), recursive = TRUE, showWarnings = FALSE)
  
  if (!requireNamespace("sfarrow", quietly = TRUE)) {
    message("Instalando el paquete 'sfarrow' para exportar GeoParquet...")
    tryCatch({
      install.packages("sfarrow", repos = "https://cloud.r-project.org", quiet = TRUE)
    }, error = function(e) {
      message("⚠️ No se pudo instalar 'sfarrow'. Intentando guardar con 'arrow' básico serializando en WKB...")
    })
  }
  
  if (requireNamespace("sfarrow", quietly = TRUE)) {
    message("Guardando en formato GeoParquet nativo con 'sfarrow'...")
    sfarrow::st_write_parquet(df_barrido_unido, ruta_parquet)
    message("✅ GeoParquet guardado con éxito en: ", ruta_parquet)
  } else if (requireNamespace("arrow", quietly = TRUE)) {
    message("Guardando en formato Parquet estándar con 'arrow' (WKB)...")
    df_wkb <- as.data.frame(df_barrido_unido)
    df_wkb$geometry <- unclass(sf::st_as_binary(sf::st_geometry(df_barrido_unido)))
    arrow::write_parquet(df_wkb, ruta_parquet)
    message("✅ Parquet (WKB) guardado con éxito en: ", ruta_parquet)
  } else {
    message("❌ No se encontró 'arrow' ni 'sfarrow' instalados. No se pudo guardar el archivo Parquet.")
  }
}
# 
# # Para cargar desde el GPKG y unificarlas:
# # capas_barrido_gpkg <- cargar_capas_barrido(formato = "GPKG")
# # df_barrido_gpkg_unido <- unificar_capas_barrido(capas_barrido_gpkg)
# ==============================================================================


