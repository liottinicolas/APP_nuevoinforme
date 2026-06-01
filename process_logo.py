import numpy as np
from PIL import Image

def process_logo_original_colors():
    # Load image
    img = Image.open('logoazul.png').convert('RGBA')
    width, height = img.size
    arr = np.array(img)

    # BFS from corners/borders to find the outer white background
    visited = np.zeros((height, width), dtype=bool)
    is_bg = np.zeros((height, width), dtype=bool)

    queue = []
    # Add border pixels that are white
    for x in range(width):
        for y in [0, height - 1]:
            if arr[y, x, 0] > 230 and arr[y, x, 1] > 230 and arr[y, x, 2] > 230:
                queue.append((x, y))
                visited[y, x] = True
    for y in range(height):
        for x in [0, width - 1]:
            if arr[y, x, 0] > 230 and arr[y, x, 1] > 230 and arr[y, x, 2] > 230:
                if not visited[y, x]:
                    queue.append((x, y))
                    visited[y, x] = True

    while queue:
        cx, cy = queue.pop(0)
        is_bg[cy, cx] = True
        for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < width and 0 <= ny < height:
                if not visited[ny, nx]:
                    # If it is white/off-white (RGB > 215)
                    if arr[ny, nx, 0] > 215 and arr[ny, nx, 1] > 215 and arr[ny, nx, 2] > 215:
                        visited[ny, nx] = True
                        queue.append((nx, ny))

    # Construct the new image keeping original colors
    new_arr = np.copy(arr)
    
    # Smooth edges of background to avoid jagged border
    for y in range(height):
        for x in range(width):
            if is_bg[y, x]:
                new_arr[y, x] = [0, 0, 0, 0]
            else:
                # Anti-aliasing for pixels on the edge of the background
                # If a pixel is very bright (almost white) and near a background pixel, make it semi-transparent
                r, g, b, a = arr[y, x]
                brightness = (int(r) + int(g) + int(b)) / 3.0
                if brightness > 230:
                    # Check if there is a background pixel nearby
                    is_near_bg = False
                    for dx in [-1, 0, 1]:
                        for dy in [-1, 0, 1]:
                            nx, ny = x + dx, y + dy
                            if 0 <= nx < width and 0 <= ny < height:
                                if is_bg[ny, nx]:
                                    is_near_bg = True
                                    break
                        if is_near_bg:
                            break
                    if is_near_bg:
                        # Make it semi-transparent based on how close it is to white
                        alpha = int(255 * (255 - brightness) / 25.0)
                        alpha = max(0, min(255, alpha))
                        new_arr[y, x] = [r, g, b, alpha]

    out_img = Image.fromarray(new_arr)
    out_img.save('logoazul_transparent.png', 'PNG')
    print("SUCCESS ORIGINAL COLORS")

if __name__ == '__main__':
    process_logo_original_colors()
