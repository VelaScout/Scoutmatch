"""Deterministic local document tools: validated input, exclusive publish, structural verification."""
from __future__ import annotations
import io
import os
from pathlib import Path
from xml.sax.saxutils import escape
from .tools import Result, ToolError


def destination(env, path, suffix):
    target = env.resolve(path, for_write=True)
    if target.suffix.lower() != suffix:
        raise ToolError(f'Dateiendung muss {suffix} sein.')
    if target.exists():
        raise ToolError('Datei existiert bereits. Bitte einen neuen Dateinamen wählen.')
    return target


def publish(target, data):
    target.parent.mkdir(parents=True, exist_ok=True)
    # O_EXCL also protects against a concurrent creator; never truncate another file.
    try:
        with target.open('xb') as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
    except FileExistsError as exc:
        raise ToolError('Datei existiert bereits. Bitte einen neuen Dateinamen wählen.') from exc
    except OSError:
        target.unlink(missing_ok=True)
        raise
    return Result(True, f'Erstellt: {target}', verified=True, data={'path': str(target), 'bytes': len(data)})


def text(value, label, limit):
    if not isinstance(value, str) or not value.strip() or len(value) > limit:
        raise ToolError(f'{label}: nichtleeren Text mit höchstens {limit} Zeichen angeben.')
    return value.strip()


def create_presentation(env, path: str, title: str, slides: list):
    target = destination(env, path, '.pptx')
    title = text(title, 'Titel', 120)
    if not isinstance(slides, list) or not 1 <= len(slides) <= 40:
        raise ToolError('Bitte 1 bis 40 Folien angeben.')
    clean = []
    for slide in slides:
        if not isinstance(slide, dict):
            raise ToolError('Jede Folie braucht title und bullets.')
        heading = text(slide.get('title'), 'Folientitel', 100)
        bullets = slide.get('bullets')
        if not isinstance(bullets, list) or not 1 <= len(bullets) <= 6:
            raise ToolError('Je Folie 1 bis 6 Stichpunkte angeben; längere Inhalte aufteilen.')
        clean.append((heading, [text(b, 'Stichpunkt', 180) for b in bullets]))
    try:
        from pptx import Presentation
        from pptx.util import Inches, Pt
        from pptx.dml.color import RGBColor
    except ImportError as exc:
        raise ToolError('PowerPoint-Modul fehlt. AKTUALISIEREN.command ausführen.') from exc
    deck = Presentation()
    deck.slide_width, deck.slide_height = Inches(13.333), Inches(7.5)
    deck.core_properties.title = title
    for index, (heading, bullets) in enumerate(clean):
        slide = deck.slides.add_slide(deck.slide_layouts[6])
        slide.background.fill.solid()
        slide.background.fill.fore_color.rgb = RGBColor(245, 247, 251)
        def box(x, y, w, h):
            frame = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h)).text_frame
            frame.word_wrap = True
            return frame
        frame = box(.7, .45, 11.9, .95)
        frame.text = heading
        for run in frame.paragraphs[0].runs:
            run.font.size, run.font.bold = Pt(30), True
            run.font.color.rgb = RGBColor(24, 45, 76)
        frame = box(.8, 1.65, 11.6, 5.1)
        for i, bullet in enumerate(bullets):
            p = frame.paragraphs[0] if i == 0 else frame.add_paragraph()
            p.text = '• ' + bullet
            p.font.size = Pt(20)
            p.space_after = Pt(12)
        footer = box(.8, 7.03, 11.7, .3)
        footer.text = f'{title[:75]}  |  {index + 1} / {len(clean)}'
        footer.paragraphs[0].font.size = Pt(10)
    buf = io.BytesIO()
    deck.save(buf)
    data = buf.getvalue()
    check = Presentation(io.BytesIO(data))
    if len(check.slides) != len(clean):
        raise ToolError('Präsentationsprüfung fehlgeschlagen.')
    return publish(target, data)


def _pdf_font():
    try:
        from reportlab.pdfbase import pdfmetrics
        from reportlab.pdfbase.ttfonts import TTFont
    except ImportError as exc:
        raise ToolError('PDF-Modul fehlt. AKTUALISIEREN.command ausführen.') from exc
    for candidate in ('/System/Library/Fonts/Supplemental/Arial.ttf',
                      '/Library/Fonts/Arial.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'):
        if Path(candidate).is_file():
            if 'AtlasDocument' not in pdfmetrics.getRegisteredFontNames():
                pdfmetrics.registerFont(TTFont('AtlasDocument', candidate))
            return 'AtlasDocument'
    return 'Helvetica'


def render_pdf(title: str, blocks: list[tuple[str, object]]) -> bytes:
    """blocks: ('h1'|'h2'|'p'|'bullet', text) oder ('table', [[...], ...]). Prüft Zeichen und Ergebnis."""
    try:
        from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
        from reportlab.lib.styles import getSampleStyleSheet
        from reportlab.lib.pagesizes import A4
        from reportlab.lib import colors
        from reportlab.pdfbase import pdfmetrics
        from pypdf import PdfReader
    except ImportError as exc:
        raise ToolError('PDF-Modul fehlt. AKTUALISIEREN.command ausführen.') from exc
    font = _pdf_font()
    every = title + ''.join(str(v) if not isinstance(v, list) else ''.join(map(str, sum(v, []))) for _, v in blocks)
    # Fail explicitly instead of silently replacing unsupported characters with black squares.
    charset = getattr(pdfmetrics.getFont(font).face, 'charToGlyph', None)
    if charset is not None:
        unsupported = {c for c in every if not c.isspace() and ord(c) not in charset}
        if unsupported:
            raise ToolError('PDF-Schrift unterstützt diese Zeichen nicht: ' + ''.join(sorted(unsupported))[:50])
    else:
        try:
            every.encode('cp1252')
        except UnicodeEncodeError as exc:
            raise ToolError('Für diesen Text fehlt eine passende Unicode-Schrift.') from exc
    styles = getSampleStyleSheet()
    for name in ('Title', 'Heading1', 'Heading2', 'BodyText'):
        styles[name].fontName = font
    styles['BodyText'].fontSize = 11
    styles['BodyText'].leading = 16
    story = [Paragraph(escape(title), styles['Title']), Spacer(1, 12)]
    for kind, value in blocks:
        if kind == 'table':
            rows = [[Paragraph(escape(str(c)), styles['BodyText']) for c in row] for row in value][:2000]
            if rows:
                table = Table(rows, repeatRows=1)
                table.setStyle(TableStyle([('GRID', (0, 0), (-1, -1), 0.4, colors.grey),
                                           ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#E8EEF7')),
                                           ('VALIGN', (0, 0), (-1, -1), 'TOP')]))
                story += [table, Spacer(1, 10)]
            continue
        style = {'h1': 'Heading1', 'h2': 'Heading2'}.get(kind, 'BodyText')
        text = escape(str(value))
        if kind == 'bullet':
            text = '• ' + text
        story += [Paragraph(text if str(value).strip() else ' ', styles[style]), Spacer(1, 4)]
    buf = io.BytesIO()
    SimpleDocTemplate(buf, pagesize=A4, title=title, author='ATLAS',
                      leftMargin=50, rightMargin=50, topMargin=50, bottomMargin=50).build(story)
    data = buf.getvalue()
    check = PdfReader(io.BytesIO(data))
    if not check.pages or not any(p.extract_text() for p in check.pages):
        raise ToolError('PDF-Prüfung fehlgeschlagen.')
    return data


def text_blocks(content: str) -> list[tuple[str, str]]:
    """Einfaches Markdown: # Überschrift, ## Unterüberschrift, - Aufzählung, sonst Absatz."""
    blocks = []
    for line in content.split('\n'):
        stripped = line.strip()
        if stripped.startswith('## '):
            blocks.append(('h2', stripped[3:]))
        elif stripped.startswith('# '):
            blocks.append(('h1', stripped[2:]))
        elif stripped[:2] in ('- ', '* ', '• '):
            blocks.append(('bullet', stripped[2:]))
        else:
            blocks.append(('p', stripped))
    return blocks


def create_pdf(env, path: str, title: str, content: str):
    target = destination(env, path, '.pdf')
    title = text(title, 'Titel', 160)
    content = text(content, 'Inhalt', 100_000)
    return publish(target, render_pdf(title, text_blocks(content)))


# ---------------------------------------------------------------------------------------------
# Word, PowerPoint lesen, Bearbeiten mit Sicherung, Umwandeln
# ---------------------------------------------------------------------------------------------

def _docx():
    try:
        import docx
    except ImportError as exc:
        raise ToolError('Word-Modul (python-docx) fehlt. AKTUALISIEREN.command ausführen.') from exc
    return docx


def read_docx(path: Path) -> str:
    """Text mit Überschriften-Markierung und Tabellen (Zeilen mit Tabulatoren)."""
    document = _docx().Document(str(path))
    lines = []
    for paragraph in document.paragraphs:
        style = (paragraph.style.name or '').lower() if paragraph.style is not None else ''
        prefix = '# ' if style in ('title', 'heading 1') else '## ' if style.startswith('heading') else ''
        prefix = '- ' if 'list' in style else prefix
        lines.append(prefix + paragraph.text)
    for number, table in enumerate(document.tables, 1):
        lines.append(f'[Tabelle {number}]')
        lines += ['\t'.join(cell.text for cell in row.cells) for row in table.rows]
    return '\n'.join(lines)


def read_pptx(path: Path) -> str:
    try:
        from pptx import Presentation
    except ImportError as exc:
        raise ToolError('PowerPoint-Modul fehlt. AKTUALISIEREN.command ausführen.') from exc
    deck = Presentation(str(path))
    out = []
    for number, slide in enumerate(deck.slides, 1):
        texts = [shape.text_frame.text for shape in slide.shapes if shape.has_text_frame and shape.text_frame.text.strip()]
        out.append(f'[Folie {number}]\n' + '\n'.join(texts))
        if slide.has_notes_slide and slide.notes_slide.notes_text_frame.text.strip():
            out.append('Notizen: ' + slide.notes_slide.notes_text_frame.text)
    return '\n'.join(out)


def read_csv(path: Path) -> list[list[str]]:
    import csv
    raw = path.read_text(encoding='utf-8-sig', errors='replace')
    try:
        dialect = csv.Sniffer().sniff(raw[:4000], delimiters=';,\t')
    except csv.Error:
        dialect = csv.excel
    return [row for row in csv.reader(io.StringIO(raw), dialect)]


def docx_bytes(title: str, content: str) -> bytes:
    document = _docx().Document()
    document.core_properties.title = title
    document.add_heading(title, level=0)
    for kind, value in text_blocks(content):
        if kind == 'h1':
            document.add_heading(value, level=1)
        elif kind == 'h2':
            document.add_heading(value, level=2)
        elif kind == 'bullet':
            document.add_paragraph(value, style='List Bullet')
        elif value:
            document.add_paragraph(value)
    buf = io.BytesIO()
    document.save(buf)
    return buf.getvalue()


def create_document(env, path: str, title: str, content: str):
    """Echtes Word-Dokument (.docx) mit Überschriften, Absätzen, Aufzählungen; nach dem Speichern nachgelesen."""
    target = destination(env, path, '.docx')
    title = text(title, 'Titel', 160)
    content = text(content, 'Inhalt', 200_000)
    data = docx_bytes(title, content)
    check = _docx().Document(io.BytesIO(data))
    sample = next((v for k, v in text_blocks(content) if v), '')
    if sample and sample not in '\n'.join(p.text for p in check.paragraphs):
        raise ToolError('Word-Prüfung fehlgeschlagen.')
    return publish(target, data)


def backup(env, file: Path) -> Path:
    """Sicherung vor jeder Änderung einer vorhandenen Datei (in ~/.atlas-ai/sicherungen, nicht im Nutzerordner)."""
    import shutil
    import time
    folder = env.home / '.atlas-ai' / 'sicherungen' / time.strftime('%Y-%m-%d')
    folder.mkdir(parents=True, exist_ok=True)
    copy = folder / f'{time.strftime("%H%M%S")}-{file.name}'
    shutil.copy2(file, copy)
    return copy


def _existing(env, path: str, suffixes: tuple[str, ...]) -> Path:
    file = env.resolve(path, must_exist=True)
    if not file.is_file() or file.suffix.lower() not in suffixes:
        raise ToolError('Erwartet wird eine vorhandene Datei mit Endung ' + ', '.join(suffixes) + '.')
    return file


def edit_document(env, path: str, replacements: list | None = None, append: str = ''):
    """Ersetzt Textstellen und/oder hängt Text an (.docx, .txt, .md). Vorher Sicherung, danach Kontrolle."""
    file = _existing(env, path, ('.docx', '.txt', '.md'))
    pairs = []
    for item in replacements or []:
        if not isinstance(item, dict) or not isinstance(item.get('old'), str) or not item['old'] or not isinstance(item.get('new'), str):
            raise ToolError('Jede Ersetzung braucht old (nicht leer) und new.')
        pairs.append((item['old'], item['new']))
    if not pairs and not (isinstance(append, str) and append.strip()):
        raise ToolError('Nichts zu ändern: replacements oder append angeben.')
    if file.suffix.lower() == '.docx':
        document = _docx().Document(str(file))
        paragraphs = list(document.paragraphs) + [p for t in document.tables for r in t.rows for c in r.cells for p in c.paragraphs]
        for old, new in pairs:
            hits = [p for p in paragraphs if old in p.text]
            if not hits:
                raise ToolError(f'Textstelle nicht gefunden: „{old[:80]}“. Datei unverändert.')
            for paragraph in hits:
                replaced = paragraph.text.replace(old, new)
                runs = paragraph.runs
                if runs:          # Formatierung des ersten Abschnitts bleibt erhalten
                    runs[0].text = replaced
                    for run in runs[1:]:
                        run.text = ''
                else:
                    paragraph.add_run(replaced)
        for kind, value in text_blocks(append or ''):
            if not value:
                continue
            if kind in ('h1', 'h2'):
                document.add_heading(value, level=1 if kind == 'h1' else 2)
            else:
                document.add_paragraph(value, style='List Bullet' if kind == 'bullet' else None)
        buf = io.BytesIO()
        document.save(buf)
        data = buf.getvalue()
        new_text = read_docx_bytes(data)
    else:
        content = file.read_text(encoding='utf-8')
        for old, new in pairs:
            if old not in content:
                raise ToolError(f'Textstelle nicht gefunden: „{old[:80]}“. Datei unverändert.')
            content = content.replace(old, new)
        if append and append.strip():
            content = content.rstrip('\n') + '\n' + append.strip() + '\n'
        data = content.encode('utf-8')
        new_text = content
    for old, new in pairs:
        if new and new not in new_text:
            raise ToolError('Kontrolle fehlgeschlagen. Datei unverändert.')
    saved = backup(env, file)
    temp = file.with_name(f'.{file.name}.atlas-neu')
    temp.write_bytes(data)
    os.replace(temp, file)          # atomar: nie eine halb geschriebene Datei
    return Result(True, f'Geändert: {file} ({len(pairs)} Ersetzungen{", Text angehängt" if append else ""}). '
                        f'Sicherung der vorherigen Fassung: {saved}', verified=True,
                  data={'path': str(file), 'backup': str(saved)})


def read_docx_bytes(data: bytes) -> str:
    document = _docx().Document(io.BytesIO(data))
    return '\n'.join([p.text for p in document.paragraphs] +
                     [c.text for t in document.tables for r in t.rows for c in r.cells])


def edit_spreadsheet(env, path: str, cells: dict | None = None, append_rows: list | None = None, sheet: str = ''):
    """Zellen setzen (z. B. {"B2": 120, "C5": "=SUM(C2:C4)"}) und/oder Zeilen anhängen. Mit Sicherung und Kontrolle."""
    import csv
    import re
    file = _existing(env, path, ('.xlsx', '.csv'))
    cells = cells or {}
    if not isinstance(cells, dict) or not all(isinstance(k, str) and re.fullmatch(r'[A-Za-z]{1,3}[1-9]\d{0,6}', k) for k in cells):
        raise ToolError('cells: Zuordnung wie {"B2": 120} erwartet.')
    rows = append_rows or []
    if not isinstance(rows, list) or not all(isinstance(r, list) for r in rows):
        raise ToolError('append_rows: Liste von Zeilen (Listen) erwartet.')
    if not cells and not rows:
        raise ToolError('Nichts zu ändern.')
    from .tools import cell_value
    if file.suffix.lower() == '.xlsx':
        try:
            from openpyxl import load_workbook
        except ImportError as exc:
            raise ToolError('Excel-Modul fehlt. AKTUALISIEREN.command ausführen.') from exc
        book = load_workbook(str(file))
        if sheet and sheet not in book.sheetnames:
            raise ToolError(f'Blatt „{sheet}“ gibt es nicht. Vorhanden: {", ".join(book.sheetnames)}')
        ws = book[sheet] if sheet else book.active
        for ref, value in cells.items():
            ws[ref.upper()] = cell_value(value)
        for row in rows:
            ws.append([cell_value(v) for v in row])
        buf = io.BytesIO()
        book.save(buf)
        data = buf.getvalue()
        check = load_workbook(io.BytesIO(data))[ws.title]
        for ref, value in cells.items():
            if check[ref.upper()].value != cell_value(value):
                raise ToolError('Kontrolle fehlgeschlagen. Datei unverändert.')
    else:
        table = read_csv(file)
        for ref, value in cells.items():
            col = 0
            letters = re.match(r'[A-Za-z]+', ref)[0].upper()
            for ch in letters:
                col = col * 26 + ord(ch) - 64
            row_index = int(ref[len(letters):]) - 1
            while len(table) <= row_index:
                table.append([])
            while len(table[row_index]) < col:
                table[row_index].append('')
            table[row_index][col - 1] = str(value)
        table += [[str(v) for v in row] for row in rows]
        out = io.StringIO()
        csv.writer(out, delimiter=';').writerows(table)
        data = out.getvalue().encode('utf-8')
    saved = backup(env, file)
    temp = file.with_name(f'.{file.name}.atlas-neu')
    temp.write_bytes(data)
    os.replace(temp, file)
    return Result(True, f'Tabelle geändert: {file} ({len(cells)} Zellen, {len(rows)} neue Zeilen). Sicherung: {saved}',
                  verified=True, data={'path': str(file), 'backup': str(saved)})


def free_name(target: Path) -> Path:
    if not target.exists():
        return target
    for number in range(2, 1000):
        candidate = target.with_name(f'{target.stem}-{number}{target.suffix}')
        if not candidate.exists():
            return candidate
    raise ToolError('Kein freier Dateiname gefunden.')


def convert_document(env, path: str, to: str = 'pdf', target: str = ''):
    """Wandelt .docx/.txt/.md/.csv/.xlsx/.pptx in PDF, oder .txt/.md in Word. Original bleibt unverändert."""
    source = _existing(env, path, ('.docx', '.txt', '.md', '.csv', '.xlsx', '.pptx'))
    kind = (to or 'pdf').lower().lstrip('.')
    if kind not in ('pdf', 'docx'):
        raise ToolError('Ziel: pdf oder docx.')
    out = env.resolve(target, for_write=True) if target else source.with_suffix('.' + kind)
    if out.suffix.lower() != '.' + kind:
        raise ToolError(f'Zieldatei muss auf .{kind} enden.')
    out = free_name(out)            # nie überschreiben
    title = source.stem.replace('_', ' ').replace('-', ' ')
    suffix = source.suffix.lower()
    if suffix == '.docx':
        blocks = text_blocks(read_docx(source))
        plain = read_docx(source)
    elif suffix in ('.txt', '.md'):
        plain = source.read_text(encoding='utf-8', errors='replace')
        blocks = text_blocks(plain)
    elif suffix == '.csv':
        rows = read_csv(source)
        blocks, plain = [('table', rows)], '\n'.join(' '.join(r) for r in rows)
    elif suffix == '.xlsx':
        from openpyxl import load_workbook
        book = load_workbook(str(source), data_only=True)
        blocks, plain = [], ''
        for ws in book.worksheets[:10]:
            rows = [['' if v is None else str(v) for v in row] for row in ws.iter_rows(values_only=True)]
            blocks += [('h2', ws.title), ('table', rows)]
            plain += '\n'.join(' '.join(r) for r in rows)
    else:
        plain = read_pptx(source)
        blocks = [('h2', line[1:-1]) if line.startswith('[Folie') else ('p', line) for line in plain.split('\n')]
    if not plain.strip():
        raise ToolError('Quelldatei enthält keinen Text.')
    if kind == 'docx':
        if suffix not in ('.txt', '.md'):
            raise ToolError('Nach Word lassen sich nur .txt und .md umwandeln.')
        data = docx_bytes(title, plain)
    else:
        data = render_pdf(title, blocks)
        from pypdf import PdfReader
        produced = ''.join(p.extract_text() for p in PdfReader(io.BytesIO(data)).pages)
        words = [w for w in plain.split() if len(w) > 3][:5]
        if words and not any(w in produced for w in words):
            raise ToolError('PDF-Kontrolle fehlgeschlagen: Inhalt nicht wiedergefunden.')
    result = publish(out, data)
    result.output = f'Umgewandelt: {source.name} → {out}. Original unverändert.'
    return result


def compare_documents(env, path_a: str, path_b: str):
    """Vergleicht zwei Dokumente (Text, Word, PDF, Excel, CSV, PowerPoint) zeilenweise – ohne Modell, nachprüfbar."""
    import difflib
    import re
    from .tools import read_file
    texts = []
    for path in (path_a, path_b):
        result = read_file(env, path, max_chars=60_000)
        # Formatmarken (Überschrift „# “, Aufzählung „- “) zählen nicht als Inhaltsunterschied.
        lines = [re.sub(r'^(#{1,3}|[-*•])\s+', '', line.strip()) for line in result.output.splitlines()]
        texts.append([line for line in lines if line and not line.startswith('[Seite ')])
    a, b = texts
    ratio = difflib.SequenceMatcher(None, a, b, autojunk=False).ratio()
    removed = [line for line in difflib.ndiff(a, b) if line.startswith('- ')]
    added = [line for line in difflib.ndiff(a, b) if line.startswith('+ ')]
    if not removed and not added:
        return Result(True, 'Die beiden Dokumente sind inhaltlich gleich (gleicher Text).', verified=True,
                      data={'similarity': 1.0, 'added': 0, 'removed': 0})
    shown = [f'Nur in {Path(path_a).name}: {line[2:]}' for line in removed[:40]] + \
            [f'Nur in {Path(path_b).name}: {line[2:]}' for line in added[:40]]
    head = (f'Übereinstimmung {ratio:.0%}. {len(removed)} Zeilen nur im ersten, {len(added)} Zeilen nur im zweiten Dokument'
            + (' (gekürzt).' if len(removed) > 40 or len(added) > 40 else '.'))
    return Result(True, head + '\n' + '\n'.join(shown), verified=True,
                  data={'similarity': round(ratio, 3), 'added': len(added), 'removed': len(removed)})
