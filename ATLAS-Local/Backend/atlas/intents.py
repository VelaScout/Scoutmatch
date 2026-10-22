"""Explicit local commands only: no eval, shell strings or model-selected actions."""
import ast
from decimal import Decimal, localcontext, InvalidOperation
import re

TARGETS = {
 'rechner':('app','calculator'), 'taschenrechner':('app','calculator'), 'calculator':('app','calculator'),
 'finder':('app','finder'), 'notizen':('app','notes'), 'notes':('app','notes'),
 'kalender':('app','calendar'), 'calendar':('app','calendar'), 'safari':('app','safari'),
 'textedit':('app','textedit'), 'downloads':('folder','downloads'),
 'dokumente':('folder','documents'), 'documents':('folder','documents'),
 'schreibtisch':('folder','desktop'), 'desktop':('folder','desktop'),
}

def calculate(expression):
    if len(expression)>160 or not re.fullmatch(r'[\d\s.,+*/()−×÷-]+',expression):return None
    expression=expression.replace(',','.').replace('−','-').replace('×','*').replace('÷','/')
    try:
        tree=ast.parse(expression.strip(),mode='eval')
        if len(list(ast.walk(tree)))>60:return None
        def visit(node,depth=0):
            if depth>12:raise ValueError()
            if isinstance(node,ast.Constant) and type(node.value) in (int,float):
                # Use source spelling rather than binary floating-point arithmetic.
                value=Decimal(ast.get_source_segment(expression.strip(),node))
            elif isinstance(node,ast.UnaryOp) and isinstance(node.op,(ast.UAdd,ast.USub)):
                value=visit(node.operand,depth+1)*(-1 if isinstance(node.op,ast.USub) else 1)
            elif isinstance(node,ast.BinOp) and isinstance(node.op,(ast.Add,ast.Sub,ast.Mult,ast.Div)):
                left,right=visit(node.left,depth+1),visit(node.right,depth+1)
                if isinstance(node.op,ast.Add):value=left+right
                elif isinstance(node.op,ast.Sub):value=left-right
                elif isinstance(node.op,ast.Mult):value=left*right
                else:value=left/right
            else:raise ValueError()
            if not value.is_finite() or abs(value)>Decimal('1e15'):raise ValueError()
            return value
        with localcontext() as ctx:
            ctx.prec=28
            value=visit(tree.body)
            rounded=value.quantize(Decimal('0.000001'))
            text=format(rounded,'f').rstrip('0').rstrip('.') if '.' in format(rounded,'f') else format(rounded,'f')
            if text=='-0':text='0'
            if rounded!=value:text='Ungefähr '+text
            return text.replace('.',',')+'.'
    except (SyntaxError,ValueError,ArithmeticError,InvalidOperation):return None

WORD_OPERATORS=[('multipliziert mit','*'),('geteilt durch','/'),('divided by','/'),('times','*'),('plus','+'),('minus','-'),('mal','*')]

def normalize_expression(text):
    """Spoken arithmetic to symbols, including percentages ("15 % von 80" -> 15/100*80)."""
    question=text.lower().strip()
    for word,op in WORD_OPERATORS:
        question=re.sub(r'\b'+word+r'\b',op,question)
    question=re.sub(r'(\d+(?:[.,]\d+)?)\s*(?:%|prozent|percent)\s*(?:von|of)\s*',r'\1/100*',question)
    question=re.sub(r'(\d+(?:[.,]\d+)?)\s*(?:%|prozent|percent)',r'(\1/100)',question)
    return question

def plan(text):
    # Strip the trusted native date prefix only, not arbitrary quoted text.
    text=re.sub(r'^\[Kontext:[^\n]*\]\n','',text).strip()
    t=text.lower().strip()
    direct=re.fullmatch(r'(?:bitte\s+)?(?:öffne|starte|open)\s+(.+?)[.!]?\s*',t)
    if direct:
        names=re.split(r'\s+(?:und|and)\s+|,\s*',direct[1])
        if 1<=len(names)<=3 and all(n in TARGETS for n in names):
            return {'kind':'tools','steps':[{'name':'local_open','input':dict(zip(('kind','target'),TARGETS[n]))} for n in dict.fromkeys(names)]}
    memory=re.fullmatch(r'(?:bitte\s+)?(?:merk dir|merke dir|remember)(?:\s+bitte)?[:,]?\s+(?:(?:dass|that)\s+)?(.+?)[.!]?\s*',text,re.I|re.S)
    if memory and 1<=len(memory[1])<=1000:
        content=memory[1].strip()
        return {'kind':'tools','steps':[{'name':'remember','input':{'content':content[:1].upper()+content[1:],'category':'Sonstiges'}}]}
    if t.rstrip('.?!') in ('was weißt du über mich','was hast du dir gemerkt','zeige meine erinnerungen','what do you remember about me'):
        return {'kind':'tools','steps':[{'name':'list_memories','input':{}}]}
    # Formathinweise hinter der Rechenfrage („Antworte nur mit der Zahl.“, „Kurz bitte.“) ändern das Ergebnis nicht.
    t=re.sub(r'(?<=[?.!])\s+(?:antworte|antwort|bitte|nur|kurz|answer|just|only|reply)\b[^?]*$','',t).strip()
    question=re.sub(r'^(?:was ist|was sind|was ergibt|wie viel ist|wieviel ist|wie viel sind|wieviel sind|wie viel macht|berechne|rechne|what is|calculate)\s+','',t)
    question=re.sub(r'\s*(?:[?=]|\.(?!\d))$','',question)
    question=normalize_expression(question)
    if any(op in question for op in '+-*/×÷−'):
        answer=calculate(question)
        if answer is not None:return {'kind':'answer','answer':answer}
    return {'kind':'chat'}
