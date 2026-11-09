"""Writes docs/samples/droptimize-demo.docx (python3 make-demo-docx.py droptimize-demo.docx; needs python-docx and Pillow,
a dev tool only): a two-page Word document for trying Word → PDF.
It has what the built-in reader handles (headings, styles, lists, a table, a picture, a page break)
and what only Word or Pages keep (a header, a footer with page numbers)."""
import io, sys
from PIL import Image, ImageDraw, ImageFont
from docx import Document
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

OUT = sys.argv[1]
INK, MINT, GREY = RGBColor(0x0E, 0x0E, 0x0F), RGBColor(0x1F, 0x9D, 0x6A), RGBColor(0x6B, 0x6B, 0x6F)

def chart():
    """A bar chart: how much smaller each kind of file got."""
    W, H = 1600, 760
    img = Image.new('RGB', (W, H), 'white'); d = ImageDraw.Draw(img)
    font = lambda size, bold=False: ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf' % ('-Bold' if bold else ''), size)
    d.text((60, 40), 'How much smaller each file got', fill=(14, 14, 15), font=font(44, True))
    rows = [('Photo (HEIC → WebP)', 96), ('Screenshot (PNG)', 87), ('Video (MOV → WebM)', 97), ('Report (PDF)', 89)]
    top, left, right, bar = 150, 560, 1480, 90
    for i, (label, pct) in enumerate(rows):
        y = top + i * 140
        d.text((60, y + 22), label, fill=(60, 60, 64), font=font(36))
        d.rounded_rectangle((left, y, right, y + bar), radius=18, fill=(236, 236, 240))
        d.rounded_rectangle((left, y, left + (right - left) * pct / 100, y + bar), radius=18, fill=(61, 220, 151))
        d.text((left + 24, y + 20), f'−{pct}%', fill=(14, 14, 15), font=font(40, True))
    buf = io.BytesIO(); img.save(buf, 'PNG'); buf.seek(0); return buf

def field(paragraph, instruction):
    """A Word field (PAGE, NUMPAGES): only Word and Pages fill these in."""
    simple = OxmlElement('w:fldSimple'); simple.set(qn('w:instr'), instruction)
    run = OxmlElement('w:r'); text = OxmlElement('w:t'); text.text = '1'; run.append(text); simple.append(run)
    paragraph._p.append(simple)

def shade(cell, fill):
    props = cell._tc.get_or_add_tcPr(); shd = OxmlElement('w:shd')
    shd.set(qn('w:val'), 'clear'); shd.set(qn('w:color'), 'auto'); shd.set(qn('w:fill'), fill); props.append(shd)

doc = Document()
section = doc.sections[0]
section.page_width, section.page_height = Cm(21), Cm(29.7)                 # A4
for side in ('left_margin', 'right_margin', 'top_margin', 'bottom_margin'): setattr(section, side, Cm(2.5))
doc.styles['Normal'].font.size = Pt(11)

# Header and footer (Word and Pages keep them; the built-in reader doesn't)
head = section.header.paragraphs[0]; head.alignment = WD_ALIGN_PARAGRAPH.RIGHT
r = head.add_run('Droptimize · Word → PDF demo'); r.font.size = Pt(9); r.font.color.rgb = GREY
foot = section.footer.paragraphs[0]; foot.alignment = WD_ALIGN_PARAGRAPH.CENTER
r = foot.add_run('Page '); r.font.size = Pt(9); r.font.color.rgb = GREY
field(foot, 'PAGE'); r = foot.add_run(' of '); r.font.size = Pt(9); r.font.color.rgb = GREY; field(foot, 'NUMPAGES')

doc.add_heading('Launch Plan: Droptimize for Mac', level=0)
p = doc.add_paragraph(); r = p.add_run('A one-page summary for the team, with an appendix. Drop this file on the bubble to turn it into a PDF.')
r.italic = True; r.font.color.rgb = GREY

doc.add_heading('Why it matters', level=1)
p = doc.add_paragraph('Shrinking a file is a solved problem. ')
r = p.add_run('The detour around it is not: '); r.bold = True
p.add_run('find a website, upload, wait, download, unzip, find the file again. Droptimize removes the detour. '
          'You drop the file where you already are, and the result is saved next to the original and copied to the clipboard.')

doc.add_heading('What ships first', level=1)
for item in ['Images: WebP, AVIF, JPG, PNG and HEIC, compression to a size, half size and background removal.',
             'Videos: WebM by default, AV1, MP4, HEVC and GIF, compression to a size, resizing and muting.',
             'Documents: compress PDFs, turn pages into images, put images into a PDF, and turn Word files into PDFs.']:
    doc.add_paragraph(item, style='List Bullet')

doc.add_heading('Launch steps', level=1)
for step in ['Finish hands-on testing on a real Mac.', 'Open the store and set the Pro price ($9.99, once).',
             'Publish the launch film and the website.']:
    doc.add_paragraph(step, style='List Number')

doc.add_heading('Results so far', level=1)
table = doc.add_table(rows=1, cols=4); table.style = 'Table Grid'; table.alignment = WD_TABLE_ALIGNMENT.CENTER
for cell, text in zip(table.rows[0].cells, ['File', 'Before', 'After', 'Smaller by']):
    cell.text = ''; run = cell.paragraphs[0].add_run(text); run.bold = True; shade(cell, 'E8F8F0')
for row in [('IMG_2041.heic', '12.4 MB', '486 KB', '96%'), ('screenshot.png', '3.1 MB', '412 KB', '87%'),
            ('launch.mov', '840 MB', '24.1 MB', '97%'), ('report.pdf', '8.4 MB', '912 KB', '89%')]:
    cells = table.add_row().cells
    for i, text in enumerate(row):
        cells[i].text = text
        if i: cells[i].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.RIGHT

doc.add_picture(chart(), width=Cm(11.5))
doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER
cap = doc.add_paragraph('Figure 1. Savings on the files above.'); cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
cap.runs[0].italic = True; cap.runs[0].font.size = Pt(9); cap.runs[0].font.color.rgb = GREY

doc.add_paragraph('Drop it. Done.', style='Intense Quote')

# Page 2: the appendix heading starts a new page (a page break, as Word stores it)
appendix = doc.add_heading('Appendix: how the PDF is made', level=1)
appendix.paragraph_format.page_break_before = True
doc.add_paragraph('When Microsoft Word is installed, Droptimize asks Word to save the document as a PDF, out of sight. '
                  'The PDF then looks exactly like the document, including this page’s header and the page numbers at the bottom.')
doc.add_paragraph('Without Word, Pages does the same. Without either, Droptimize reads the document itself: the text, styles, '
                  'lists, table, picture, header and page numbers come through, but fonts that come with Office are swapped for '
                  'the closest ones a Mac has, so the card says the layout may differ.')
doc.add_heading('What to check', level=2)
for check in ['Two pages, with this appendix starting on page 2.', 'The header at the top right of each page.',
              '“Page 1 of 2” and “Page 2 of 2” at the bottom.', 'The table and the chart where they are on page 1.']:
    doc.add_paragraph(check, style='List Bullet')
doc.core_properties.title = 'Launch Plan: Droptimize for Mac'
doc.core_properties.author = 'Droptimize'
doc.save(OUT)
print('wrote', OUT)
