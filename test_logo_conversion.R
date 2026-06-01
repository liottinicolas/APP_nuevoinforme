library(png)
library(base64enc)

if (file.exists("logoazul.png")) {
  img <- readPNG("logoazul.png")
  print(dim(img))
  is_white <- (img[,,1] + img[,,2] + img[,,3]) / 3 > 0.95
  
  # Create a white image of the same dimension, with alpha channel
  new_img <- array(1, dim = c(dim(img)[1], dim(img)[2], 4))
  # Set alpha to 0 for white background pixels, 1 for the logo pixels
  new_img[,,4] <- ifelse(is_white, 0, 1)
  
  raw_png <- writePNG(new_img)
  encoded <- base64encode(raw_png)
  cat("Success! Encoded length:", nchar(encoded), "\n")
} else {
  cat("logoazul.png not found!\n")
}
