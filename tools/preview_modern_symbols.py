"""Create a labeled review sheet. Original app image files remain unchanged."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
pack = json.loads((root/'assets/sample_pack.json').read_text(encoding='utf8'))
buttons = {b['id']:b for b in pack['buttons']}
ids = ['b1','b2','b3','b4','b5','b6','b10','b15','b20','b59','b69','b63',
       'b85','b93','b94','b109','x163','x164','x166','b67','b82',
       'fruits_19','fruits_20','fruits_22']
canvas = Image.new('RGB',(1200,900),'#F3F6FA')
draw = ImageDraw.Draw(canvas)
font_path = 'C:/Windows/Fonts/segoeuib.ttf'
heading = ImageFont.truetype(font_path,30)
label_font = ImageFont.truetype(font_path,19)
draw.text((30,18),'Soft 3D · My Words',font=heading,fill='#18324D')
for i, key in enumerate(ids):
    b = buttons[key]
    x,y = (i%6)*200+10,(i//6)*204+70
    draw.rounded_rectangle((x,y,x+180,y+191),radius=18,fill='white',outline='#E0E6EF',width=2)
    picture = Image.open(root/f'assets/symbols/modern3d/{b["symbolKey"]}.png').convert('RGBA')
    picture.thumbnail((154,150),Image.Resampling.LANCZOS)
    canvas.paste(picture,(x+(180-picture.width)//2,y+8+(150-picture.height)//2),picture)
    box = draw.textbbox((0,0),b['label'],font=label_font)
    draw.text((x+(180-box[2]+box[0])//2,y+160),b['label'],font=label_font,fill='#18324D')
canvas.save(root/'docs/modern-3d-preview.png')
print('Created docs/modern-3d-preview.png')
