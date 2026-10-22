"""Small authoring aids for missing date/time readings. Never rewrites display text.
Studio owns speech-plan validation, prosody and generation. The author must retain
whether a value is a tentative work slot, wish date, deadline or count.
"""
import datetime as dt

DIGITS=('れい','いち','に','さん','よん','ご','ろく','なな','はち','きゅう')
def number(value):
    if type(value) is not int or not 0<=value<=9999: raise ValueError('supported_integer_required')
    if value<10:return DIGITS[value]
    result=''
    for unit,name,special in ((1000,'せん',{3:'さんぜん',8:'はっせん'}),(100,'ひゃく',{3:'さんびゃく',6:'ろっぴゃく',8:'はっぴゃく'}),(10,'じゅう',{})):
        digit,value=divmod(value,unit)
        if digit:result+=special.get(digit,('' if digit==1 else DIGITS[digit])+name)
    return result+(DIGITS[value] if value else '')

def clock(value):
    import re
    if not isinstance(value,str) or not re.fullmatch(r'(?:[01]\d|2[0-3]):[0-5]\d',value):raise ValueError('HHmm_required')
    hour,minute=map(int,value.split(':'))
    if hour==12: prefix='おひるの'; spoken='じゅうに'
    else:prefix='ごぜん' if hour<12 else 'ごご'; spoken={0:'れい',4:'よ',7:'しち',9:'く'}.get(hour%12,number(hour%12))
    suffix='' if minute==0 else 'はん' if minute==30 else minutes(minute)
    return 'しょうご' if hour==12 and minute==0 else prefix+spoken+'じ'+suffix

def minutes(value):
    if type(value) is not int or not 0<=value<=9999:raise ValueError('minute_count_required')
    readings={1:'いっぷん',2:'にふん',3:'さんぷん',4:'よんぷん',5:'ごふん',6:'ろっぷん',7:'ななふん',8:'はっぷん',9:'きゅうふん'}
    if value==0:return 'れいふん'
    if value%10==0:
        text=number(value)
        return text[:-1]+'っぷん' if text.endswith(('う','く')) else text+'ぷん'
    return (number(value//10*10) if value>=10 else '')+readings[value%10]

def count(value):
    if type(value) is not int or not 0<=value<=9999:raise ValueError('item_count_required')
    if value==0:return 'れいけん'
    if value%10==0:
        text=number(value)
        return text[:-1]+'っけん' if text.endswith(('う','く')) else text+'けん'
    readings={1:'いっけん',6:'ろっけん',8:'はっけん'}
    return (number(value//10*10) if value>=10 else '')+readings.get(value%10,number(value%10)+'けん')

def date(value):
    day=dt.date.fromisoformat(value)
    month={4:'し',7:'しち',9:'く'}.get(day.month,number(day.month))+'がつ'
    special={1:'ついたち',2:'ふつか',3:'みっか',4:'よっか',5:'いつか',6:'むいか',7:'なのか',8:'ようか',9:'ここのか',10:'とおか',14:'じゅうよっか',17:'じゅうしちにち',19:'じゅうくにち',20:'はつか',24:'にじゅうよっか',29:'にじゅうくにち'}
    return number(day.year)+'ねん'+month+special.get(day.day,number(day.day)+'にち')
